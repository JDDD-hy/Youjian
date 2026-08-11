alter type public.completion_reason add value if not exists 'health_check_accepted';
alter type public.completion_reason add value if not exists 'health_check_timeout';

alter type public.focus_event_type add value if not exists 'health_check_triggered';
alter type public.focus_event_type add value if not exists 'health_check_continued';
alter type public.focus_event_type add value if not exists 'health_check_satisfied_by_pause';
alter type public.focus_event_type add value if not exists 'health_check_notification_succeeded';
alter type public.focus_event_type add value if not exists 'health_check_notification_failed';
