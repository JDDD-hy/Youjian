import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { fileURLToPath } from 'node:url';

const workspace = fileURLToPath(new URL('..', import.meta.url));
const config = readFileSync(
  new URL('../supabase/config.toml', import.meta.url),
  'utf8',
);
const projectId = config.match(/^project_id\s*=\s*"([^"]+)"/m)?.[1];
assert.ok(projectId, 'Unable to read Supabase project_id.');
const container = `supabase_db_${projectId}`;

function sql(statement) {
  return execFileSync(
    'docker',
    [
      'exec',
      container,
      'psql',
      '-v',
      'ON_ERROR_STOP=1',
      '-U',
      'postgres',
      '-d',
      'postgres',
      '-Atqc',
      statement,
    ],
    { cwd: workspace, encoding: 'utf8', stdio: ['ignore', 'pipe', 'pipe'] },
  ).trim();
}

// This check is intentionally passive. Calling maintenance here would create
// the success record that the monitor is supposed to verify.
const health = JSON.parse(
  sql(`
    with expected_job as (
      select jobid,active,schedule,command
      from cron.job
      where jobname='youjian-minute-maintenance'
    ), scheduler_runs as (
      select status,start_time,end_time,
        row_number() over(order by start_time desc) position,
        lag(start_time) over(order by start_time) previous_start
      from cron.job_run_details
      where jobid=(select jobid from expected_job limit 1)
        and start_time>=now()-interval '24 hours'
    ), audit_runs as (
      select status,started_at,duration_ms,
        row_number() over(order by started_at desc,id desc) position
      from private.maintenance_runs
      where source='cron'
    ), metrics as (
      select
        (select count(*) from expected_job)::int job_count,
        coalesce((select bool_and(active) from expected_job),false) job_active,
        coalesce((select bool_and(schedule='* * * * *') from expected_job),false) schedule_valid,
        coalesce((select bool_and(command='select private.run_scheduled_minute_maintenance()') from expected_job),false) command_valid,
        (select max(start_time) from scheduler_runs) last_scheduler_run_at,
        (select status from scheduler_runs where position=1) last_scheduler_status,
        (select count(*) from scheduler_runs where status<>'succeeded')::int scheduler_failures_24h,
        (select count(*) from scheduler_runs where previous_start is not null and start_time-previous_start>interval '95 seconds')::int scheduler_gaps_24h,
        (select max(started_at) from audit_runs where status='succeeded') last_cron_success_at,
        (select count(*) from audit_runs where position<=2 and status='failed')::int consecutive_cron_failures,
        (select count(*) from private.maintenance_runs where source='cron' and started_at>=now()-interval '24 hours' and duration_ms>50000)::int slow_cron_runs_24h,
        (select count(*) from public.focus_sessions where
          (status='paused' and paused_at+interval '15 minutes'<=now()) or
          (status='focusing' and active_segment_started_at+make_interval(secs=>max_focus_seconds-accumulated_focus_seconds)<=now()) or
          (health_check_state='waiting' and status='focusing' and active_segment_started_at+make_interval(secs=>7200-accumulated_focus_seconds)<=now()) or
          (health_check_state='pending' and status='focusing' and health_check_deadline_at<=now()) or
          (health_check_state='pending' and status='paused' and paused_at+interval '5 minutes'<=now()))::int overdue_sessions,
        (select count(*) from public.focus_connection_intervals i join public.focus_sessions s on s.id=i.session_id where i.ended_at is null and s.status not in('focusing','paused'))::int orphan_open_intervals,
        (select count(*) from private.client_error_reports where occurred_at>=now()-interval '24 hours')::int client_errors_24h,
        (select count(*) from private.rpc_internal_errors where occurred_at>=now()-interval '24 hours')::int rpc_internal_errors_24h,
        (select count(*) from public.focus_commands where created_at>=now()-interval '24 hours')::int focus_commands_24h,
        (select count(*) from public.focus_commands where created_at>=now()-interval '24 hours' and result->>'ok'='false')::int focus_command_errors_24h,
        (select count(*) from public.focus_commands where created_at>=now()-interval '24 hours' and result#>>'{error,code}' in('SESSION_ALREADY_ACTIVE','SESSION_NOT_FOCUSING','SESSION_NOT_PAUSED','SESSION_NOT_FOUND','IDEMPOTENCY_KEY_REUSED'))::int state_conflicts_24h,
        (select count(*) from public.focus_sessions where completed_at>=now()-interval '24 hours' and completion_reason in('pause_timeout','focus_limit','health_check_timeout'))::int automatic_settlements_24h,
        (select count(*) from public.focus_events where occurred_at>=now()-interval '24 hours' and event_type='health_check_triggered')::int health_checks_triggered_24h,
        (select count(*) from public.focus_sessions where health_check_state='pending')::int pending_health_checks,
        (select coalesce(sum(request_count),0) from private.invite_preview_rate_buckets where bucket_kind='ip' and window_start>=date_bin(interval '5 minutes',now(),timestamptz '2000-01-01'))::int invite_preview_requests_current_window,
        (select count(*) from private.invite_preview_rate_buckets where bucket_kind='ip' and window_start>=date_bin(interval '5 minutes',now(),timestamptz '2000-01-01') and request_count>30)::int invite_rate_limited_ip_buckets,
        (select coalesce(jsonb_object_agg(error_code,total order by error_code),'{}'::jsonb) from(select error_code,count(*)::int total from private.client_error_reports where occurred_at>=now()-interval '24 hours' group by error_code)c) client_error_codes_24h,
        (select coalesce(jsonb_object_agg(error_code,total order by error_code),'{}'::jsonb) from(select error_code,count(*)::int total from private.rpc_internal_errors where occurred_at>=now()-interval '24 hours' group by error_code)c) rpc_internal_error_codes_24h,
        (select coalesce(jsonb_object_agg(completion_reason,total order by completion_reason),'{}'::jsonb) from(select completion_reason::text,count(*)::int total from public.focus_sessions where completed_at>=now()-interval '24 hours' group by completion_reason)c) settlement_reasons_24h
    )
    select jsonb_build_object(
      'job_count',job_count,
      'job_active',job_active,
      'schedule_valid',schedule_valid,
      'command_valid',command_valid,
      'last_scheduler_run_at',last_scheduler_run_at,
      'last_scheduler_status',last_scheduler_status,
      'scheduler_failures_24h',scheduler_failures_24h,
      'scheduler_gaps_24h',scheduler_gaps_24h,
      'last_cron_success_at',last_cron_success_at,
      'consecutive_cron_failures',consecutive_cron_failures,
      'slow_cron_runs_24h',slow_cron_runs_24h,
      'overdue_sessions',overdue_sessions,
      'orphan_open_intervals',orphan_open_intervals,
      'client_errors_24h',client_errors_24h,
      'client_error_codes_24h',client_error_codes_24h,
      'rpc_internal_errors_24h',rpc_internal_errors_24h,
      'rpc_internal_error_codes_24h',rpc_internal_error_codes_24h,
      'focus_commands_24h',focus_commands_24h,
      'focus_command_errors_24h',focus_command_errors_24h,
      'state_conflicts_24h',state_conflicts_24h,
      'automatic_settlements_24h',automatic_settlements_24h,
      'health_checks_triggered_24h',health_checks_triggered_24h,
      'pending_health_checks',pending_health_checks,
      'settlement_reasons_24h',settlement_reasons_24h,
      'invite_preview_requests_current_window',invite_preview_requests_current_window,
      'invite_rate_limited_ip_buckets',invite_rate_limited_ip_buckets,
      'scheduler_age_seconds',extract(epoch from(now()-last_scheduler_run_at)),
      'cron_audit_age_seconds',extract(epoch from(now()-last_cron_success_at))
    )::text from metrics;
  `),
);

const alerts = [];
if (health.job_count !== 1 || !health.job_active)
  alerts.push('CRON_JOB_MISSING_OR_INACTIVE');
if (!health.schedule_valid || !health.command_valid)
  alerts.push('CRON_CONFIGURATION_DRIFT');
if (
  health.last_scheduler_status !== 'succeeded' ||
  health.scheduler_age_seconds === null ||
  health.scheduler_age_seconds > 125
)
  alerts.push('CRON_SCHEDULER_STALE');
if (
  health.cron_audit_age_seconds === null ||
  health.cron_audit_age_seconds > 125
)
  alerts.push('CRON_AUDIT_STALE');
if (health.scheduler_failures_24h > 0) alerts.push('CRON_SCHEDULER_FAILURE');
if (health.scheduler_gaps_24h > 0) alerts.push('CRON_SCHEDULE_GAP');
if (health.consecutive_cron_failures >= 2)
  alerts.push('CONSECUTIVE_MAINTENANCE_FAILURES');
if (health.slow_cron_runs_24h > 0) alerts.push('SLOW_MAINTENANCE_RUN');
if (health.overdue_sessions > 0) alerts.push('SETTLEMENT_BACKLOG');
if (health.orphan_open_intervals > 0) alerts.push('ORPHAN_CONNECTION_INTERVAL');

process.stdout.write(
  `${JSON.stringify({ status: alerts.length ? 'alert' : 'healthy', metrics: health, alerts })}\n`,
);
if (alerts.length && process.env.YOUJIAN_ALERT_WEBHOOK_URL) {
  const response = await fetch(process.env.YOUJIAN_ALERT_WEBHOOK_URL, {
    method: 'POST',
    headers: { 'content-type': 'application/json' },
    body: JSON.stringify({
      service: 'youjian',
      status: 'alert',
      alerts,
      metrics: health,
    }),
  });
  assert.ok(response.ok, `Alert webhook returned HTTP ${response.status}.`);
}
assert.deepEqual(
  alerts,
  [],
  `Operational alerts detected: ${alerts.join(', ')}`,
);
