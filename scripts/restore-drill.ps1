$ErrorActionPreference = 'Stop'

$workspace = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$configPath = Join-Path $workspace 'supabase\config.toml'
$projectLine = Select-String -LiteralPath $configPath -Pattern '^project_id\s*=\s*"([^"]+)"$'
if (-not $projectLine) {
  throw 'Unable to read Supabase project_id.'
}

$projectId = $projectLine.Matches[0].Groups[1].Value
$sourceContainer = "supabase_db_$projectId"
$runningContainer = docker ps --filter "name=^/$sourceContainer$" --format '{{.Names}}'
if ($LASTEXITCODE -ne 0 -or $runningContainer -ne $sourceContainer) {
  throw "Expected running database container $sourceContainer. Run npm run db:start first."
}

$databaseImage = docker inspect $sourceContainer --format '{{.Config.Image}}'
if ($LASTEXITCODE -ne 0 -or -not $databaseImage) {
  throw 'Unable to identify the Supabase Postgres image.'
}

$artifactDirectory = Join-Path $workspace '.artifacts'
$schemaDump = Join-Path $artifactDirectory 'youjian-schema.dump'
$dataDump = Join-Path $artifactDirectory 'youjian-data.dump'
$resultPath = Join-Path $artifactDirectory 'restore-drill.json'
$containerSchemaDump = '/tmp/youjian-schema.dump'
$containerDataDump = '/tmp/youjian-data.dump'
$drillContainer = 'youjian_restore_' + [guid]::NewGuid().ToString('N').Substring(0, 12)
$cronWasActive = $null
New-Item -ItemType Directory -Path $artifactDirectory -Force | Out-Null

$countSql = @'
create temp table restore_counts(name text primary key, row_count bigint not null);
do $$
declare item record;
declare item_count bigint;
begin
  for item in
    select schemaname, tablename
    from pg_tables
    where schemaname in ('auth', 'private', 'public', 'supabase_migrations')
      and tablename <> 'spatial_ref_sys'
    order by schemaname, tablename
  loop
    execute format('select count(*) from %I.%I', item.schemaname, item.tablename)
      into item_count;
    insert into restore_counts values(item.schemaname || '.' || item.tablename, item_count);
  end loop;
end
$$;
select jsonb_object_agg(name, row_count order by name)::text from restore_counts;
'@

$aclSql = @'
select jsonb_build_object(
  'functions', (
    select coalesce(jsonb_object_agg(identity, acl order by identity), '{}'::jsonb)
    from (
      select format('%I.%I(%s)', n.nspname, p.proname, pg_get_function_identity_arguments(p.oid)) identity,
        jsonb_build_object(
          'anon_execute', has_function_privilege('anon', p.oid, 'execute'),
          'authenticated_execute', has_function_privilege('authenticated', p.oid, 'execute'),
          'service_role_execute', has_function_privilege('service_role', p.oid, 'execute')
        ) acl
      from pg_proc p
      join pg_namespace n on n.oid = p.pronamespace
      where n.nspname in ('auth', 'private', 'public')
    ) f
  ),
  'tables', (
    select coalesce(jsonb_object_agg(identity, state order by identity), '{}'::jsonb)
    from (
      select format('%I.%I', n.nspname, c.relname) identity,
        jsonb_build_object(
          'anon_select', has_table_privilege('anon', c.oid, 'select'),
          'anon_insert', has_table_privilege('anon', c.oid, 'insert'),
          'anon_update', has_table_privilege('anon', c.oid, 'update'),
          'anon_delete', has_table_privilege('anon', c.oid, 'delete'),
          'authenticated_select', has_table_privilege('authenticated', c.oid, 'select'),
          'authenticated_insert', has_table_privilege('authenticated', c.oid, 'insert'),
          'authenticated_update', has_table_privilege('authenticated', c.oid, 'update'),
          'authenticated_delete', has_table_privilege('authenticated', c.oid, 'delete'),
          'service_role_select', has_table_privilege('service_role', c.oid, 'select'),
          'service_role_insert', has_table_privilege('service_role', c.oid, 'insert'),
          'service_role_update', has_table_privilege('service_role', c.oid, 'update'),
          'service_role_delete', has_table_privilege('service_role', c.oid, 'delete'),
          'rls', c.relrowsecurity,
          'force_rls', c.relforcerowsecurity
        ) state
      from pg_class c
      join pg_namespace n on n.oid = c.relnamespace
      where n.nspname in ('auth', 'private', 'public') and c.relkind in ('r', 'p', 'v')
    ) t
  )
)::text;
'@

function Get-DatabaseCounts([string] $container) {
  $output = docker exec $container psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atq -c $countSql
  if ($LASTEXITCODE -ne 0) { throw "Unable to count restored tables in $container." }
  return ($output | Select-Object -Last 1).Trim()
}

function Get-DatabaseAcl([string] $container) {
  $output = docker exec $container psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atq -c $aclSql
  if ($LASTEXITCODE -ne 0) { throw "Unable to inspect database privileges in $container." }
  return ($output | Select-Object -Last 1).Trim()
}

try {
  $cronState = docker exec $sourceContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atq -c "select active from cron.job where jobname='youjian-minute-maintenance'"
  if ($LASTEXITCODE -ne 0 -or $cronState -notin @('t', 'f')) { throw 'Unable to read the maintenance Cron state.' }
  $cronWasActive = $cronState -eq 't'
  docker exec $sourceContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atq -c "update cron.job set active=false where jobname='youjian-minute-maintenance'"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to pause maintenance Cron for a consistent backup.' }
  $sourceRealtimeTables = docker exec $sourceContainer psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atq -c "select string_agg(format('%I.%I',schemaname,tablename),',' order by schemaname,tablename) from pg_publication_tables where pubname='supabase_realtime' and schemaname in('auth','private','public')"
  if ($LASTEXITCODE -ne 0 -or -not $sourceRealtimeTables) { throw 'Unable to read the realtime publication.' }

  docker exec $sourceContainer pg_dump -U postgres -d postgres -Fc --schema-only -n auth -n private -n public -n supabase_migrations -f $containerSchemaDump
  if ($LASTEXITCODE -ne 0) { throw 'Schema backup failed.' }
  docker exec $sourceContainer pg_dump -U postgres -d postgres -Fc --data-only -n auth -n private -n public -n supabase_migrations -f $containerDataDump
  if ($LASTEXITCODE -ne 0) { throw 'Data backup failed.' }
  $sourceCounts = Get-DatabaseCounts $sourceContainer
  $sourceAcl = Get-DatabaseAcl $sourceContainer

  docker cp "$($sourceContainer):$containerSchemaDump" $schemaDump
  if ($LASTEXITCODE -ne 0) { throw 'Unable to copy the schema backup.' }
  docker cp "$($sourceContainer):$containerDataDump" $dataDump
  if ($LASTEXITCODE -ne 0) { throw 'Unable to copy the data backup.' }

  docker run -d --name $drillContainer `
    -e POSTGRES_PASSWORD=postgres `
    -e POSTGRES_USER=supabase_admin `
    -e POSTGRES_DB=postgres `
    -e JWT_SECRET=restore-drill-jwt-secret-with-at-least-32-characters `
    $databaseImage | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to start an isolated Postgres restore target.' }

  $ready = $false
  for ($attempt = 0; $attempt -lt 60; $attempt++) {
    docker exec $drillContainer pg_isready -U supabase_admin -d postgres 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $ready = $true; break }
    Start-Sleep -Seconds 1
  }
  if (-not $ready) { throw 'The isolated restore target did not become ready.' }
  # The image performs a small amount of post-readiness initialization.
  Start-Sleep -Seconds 5

  docker cp $schemaDump "$($drillContainer):$containerSchemaDump"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to copy the schema backup into the restore target.' }
  docker cp $dataDump "$($drillContainer):$containerDataDump"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to copy the data backup into the restore target.' }

  $prepareSql = @'
do $$
declare item record;
begin
  for item in select evtname from pg_event_trigger
  loop
    execute format('alter event trigger %I disable', item.evtname);
  end loop;
end
$$;
drop schema if exists public cascade;
drop schema if exists auth cascade;
drop schema if exists private cascade;
drop schema if exists supabase_migrations cascade;
'@
  docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c $prepareSql
  if ($LASTEXITCODE -ne 0) { throw 'Unable to prepare the isolated restore target.' }

  docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atq -c 'create schema if not exists extensions; create extension if not exists pgcrypto with schema extensions; create extension if not exists pg_cron'
  if ($LASTEXITCODE -ne 0) { throw 'Unable to restore required database extensions.' }

  docker exec $drillContainer pg_restore -U supabase_admin -d postgres --exit-on-error $containerSchemaDump
  if ($LASTEXITCODE -ne 0) { throw 'Schema restore failed.' }
  docker exec $drillContainer pg_restore -U supabase_admin -d postgres --data-only --disable-triggers --exit-on-error $containerDataDump
  if ($LASTEXITCODE -ne 0) { throw 'Data restore failed.' }

  $restorePublicationSql = "drop publication if exists supabase_realtime; create publication supabase_realtime for table $sourceRealtimeTables;"
  docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atq -c $restorePublicationSql
  if ($LASTEXITCODE -ne 0) { throw 'Unable to restore the realtime publication.' }

  $cronActive = if ($cronWasActive) { 'true' } else { 'false' }
  $restoreCronSql = "select cron.schedule_in_database('youjian-minute-maintenance','* * * * *','select private.run_scheduled_minute_maintenance()','postgres','postgres',$cronActive);"
  docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atq -c $restoreCronSql | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to restore the maintenance Cron job.' }

  $enableEventTriggersSql = @'
do $$
declare item record;
begin
  for item in select evtname from pg_event_trigger
  loop
    execute format('alter event trigger %I enable', item.evtname);
  end loop;
end
$$;
'@
  docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -c $enableEventTriggersSql | Out-Null
  if ($LASTEXITCODE -ne 0) { throw 'Unable to re-enable restore-target event triggers.' }

  $restoredCounts = Get-DatabaseCounts $drillContainer
  if ($sourceCounts -ne $restoredCounts) {
    throw 'Restored application, Auth, and migration table counts do not match the source database.'
  }
  $restoredAcl = Get-DatabaseAcl $drillContainer
  if ($sourceAcl -ne $restoredAcl) {
    throw 'Restored function/table privileges or RLS flags do not match the source database.'
  }
  $restoredRealtimeTables = docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atq -c "select string_agg(format('%I.%I',schemaname,tablename),',' order by schemaname,tablename) from pg_publication_tables where pubname='supabase_realtime' and schemaname in('auth','private','public')"
  if ($LASTEXITCODE -ne 0 -or $sourceRealtimeTables -ne $restoredRealtimeTables) {
    throw 'Restored realtime publication does not match the source database.'
  }

  $integritySql = @'
select jsonb_build_object(
  'profile_orphans', (select count(*) from public.profiles p left join auth.users u on u.id=p.id where u.id is null),
  'member_orphans', (select count(*) from public.space_members m left join public.profiles p on p.id=m.user_id where p.id is null),
  'session_orphans', (select count(*) from public.focus_sessions s left join public.space_members m on m.id=s.member_id where m.id is null),
  'app_secret_count', (select count(*) from private.app_secrets),
  'required_rpc_count', (select count(distinct p.proname) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname='public' and p.proname in ('create_space','join_space','start_focus','pause_focus','resume_focus','end_focus','get_home_snapshot')),
  'rls_table_count', (select count(*) from pg_class c join pg_namespace n on n.oid=c.relnamespace where n.nspname='public' and c.relkind='r' and c.relrowsecurity),
  'migration_count', (select count(*) from supabase_migrations.schema_migrations),
  'cron_job_count', (select count(*) from cron.job where jobname='youjian-minute-maintenance' and schedule='* * * * *' and command='select private.run_scheduled_minute_maintenance()'),
  'realtime_table_count', (select count(*) from pg_publication_tables where pubname='supabase_realtime' and schemaname in('auth','private','public')),
  'unsafe_helper_execute_count', (select count(*) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prosecdef and p.proname in ('settle_session','finish_focus_session','run_minute_maintenance_core','run_space_maintenance','run_space_goal_maintenance') and (has_function_privilege('anon',p.oid,'execute') or has_function_privilege('authenticated',p.oid,'execute')))
)::text;
'@
  $integrity = docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U postgres -d postgres -Atq -c $integritySql
  if ($LASTEXITCODE -ne 0) { throw 'Unable to validate restored relationships.' }
  $integrityObject = $integrity | ConvertFrom-Json
  if ($integrityObject.profile_orphans -ne 0 -or $integrityObject.member_orphans -ne 0 -or $integrityObject.session_orphans -ne 0) {
    throw 'The restored database contains orphaned application records.'
  }
  if ($integrityObject.app_secret_count -lt 1 -or $integrityObject.required_rpc_count -ne 7 -or $integrityObject.rls_table_count -lt 10 -or $integrityObject.migration_count -lt 1 -or $integrityObject.cron_job_count -ne 1 -or $integrityObject.realtime_table_count -lt 1 -or $integrityObject.unsafe_helper_execute_count -ne 0) {
    throw 'The restored database is missing secrets, RPCs, migrations, Cron, Realtime, or safe ACL/RLS configuration.'
  }

  $testTarget = '/tmp/youjian-tests'
  docker cp (Join-Path $workspace 'supabase\tests') "$($drillContainer):$testTarget"
  if ($LASTEXITCODE -ne 0) { throw 'Unable to copy database tests into the restore target.' }
  docker exec $drillContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atq -c 'create extension if not exists pgtap with schema extensions'
  if ($LASTEXITCODE -ne 0) { throw 'Unable to initialize pgTAP in the restore target.' }
  $restoredTestCount = 0
  foreach ($testFile in Get-ChildItem -LiteralPath (Join-Path $workspace 'supabase\tests') -Filter '*.sql' | Sort-Object Name) {
    $testOutput = docker exec -e 'PGOPTIONS=-c client_min_messages=warning' $drillContainer psql -v ON_ERROR_STOP=1 -U postgres -d postgres -X -f "$testTarget/$($testFile.Name)" 2>&1
    if ($LASTEXITCODE -ne 0 -or ($testOutput -join "`n") -match '(?m)^not ok|Looks like you failed') {
      Write-Output ($testOutput -join "`n")
      throw "Restored database test failed: $($testFile.Name)"
    }
    $restoredTestCount++
  }

  $result = [ordered]@{
    completed_at_utc = (Get-Date).ToUniversalTime().ToString('o')
    source_database = 'postgres'
    isolated_target = $drillContainer
    database_image = $databaseImage
    restored_schemas = @('auth', 'private', 'public', 'supabase_migrations')
    verified_counts = ($restoredCounts | ConvertFrom-Json)
    integrity = $integrityObject
    restored_database_test_files = $restoredTestCount
    schema_backup_sha256 = (Get-FileHash -LiteralPath $schemaDump -Algorithm SHA256).Hash.ToLowerInvariant()
    data_backup_sha256 = (Get-FileHash -LiteralPath $dataDump -Algorithm SHA256).Hash.ToLowerInvariant()
    status = 'passed'
  }
  $result | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $resultPath -Encoding UTF8
  Write-Output "Full isolated restore drill passed. Evidence: $resultPath"
} finally {
  if ($null -ne $cronWasActive) {
    $cronValue = if ($cronWasActive) { 'true' } else { 'false' }
    docker exec $sourceContainer psql -v ON_ERROR_STOP=1 -U supabase_admin -d postgres -Atq -c "update cron.job set active=$cronValue where jobname='youjian-minute-maintenance'" 2>$null | Out-Null
  }
  docker exec $sourceContainer rm -f $containerSchemaDump $containerDataDump 2>$null | Out-Null
  if ($drillContainer -like 'youjian_restore_*') {
    docker rm -f $drillContainer 2>$null | Out-Null
  }
}
