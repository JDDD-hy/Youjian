-- Goals accepted before the rolling-period release kept their old calendar
-- boundary. Repair only goals that are still scheduled; active or completed
-- goals retain their original accounting window.
with corrected as (
  select
    g.id as goal_id,
    p.id as proposal_id,
    public.next_goal_period(s.timezone,g.period_type,p.resolved_at) as bounds
  from public.goals g
  join public.goal_proposals p on p.id=g.source_proposal_id
  join public.spaces s on s.id=g.space_id
  where g.status='scheduled'
    and p.status='accepted'
    and p.resolved_at is not null
)
update public.goals g
set starts_at=lower(corrected.bounds),ends_at=upper(corrected.bounds)
from corrected
where g.id=corrected.goal_id
  and (g.starts_at,g.ends_at) is distinct from
      (lower(corrected.bounds),upper(corrected.bounds));

with corrected as (
  select
    p.id as proposal_id,
    lower(public.next_goal_period(s.timezone,p.period_type,p.resolved_at)) as starts_at
  from public.goal_proposals p
  join public.spaces s on s.id=p.space_id
  join public.goals g on g.source_proposal_id=p.id
  where g.status='scheduled'
    and p.status='accepted'
    and p.resolved_at is not null
)
update public.goal_proposals p
set effective_period_start=corrected.starts_at
from corrected
where p.id=corrected.proposal_id
  and p.effective_period_start is distinct from corrected.starts_at;
