create extension if not exists pgcrypto with schema extensions;
create extension if not exists pg_cron with schema pg_catalog;
create schema if not exists private;
revoke all on schema private from public,anon,authenticated;
create table private.app_secrets(name text primary key,secret bytea not null check(octet_length(secret)>=32));
insert into private.app_secrets(name,secret) values('invite_hmac_key',extensions.gen_random_bytes(32));
revoke all on private.app_secrets from public,anon,authenticated;

create type public.member_role as enum ('owner', 'member');
create type public.member_status as enum ('active', 'disabled');
create type public.focus_category as enum ('study', 'work', 'reading', 'exercise', 'other');
create type public.focus_status as enum ('focusing', 'paused', 'completed', 'discarded');
create type public.completion_reason as enum ('manual_end', 'pause_timeout', 'focus_limit', 'member_disabled');
create type public.focus_event_type as enum ('started', 'paused', 'resumed', 'completed', 'connection_unconfirmed', 'reconnected');
create type public.goal_type as enum ('group_total_minutes', 'per_member_minutes', 'shared_checkin_days');
create type public.period_type as enum ('daily', 'weekly', 'monthly');
create type public.proposal_status as enum ('pending', 'accepted', 'rejected', 'expired');
create type public.goal_vote as enum ('accepted', 'rejected');
create type public.goal_status as enum ('scheduled', 'active', 'completed', 'failed');
