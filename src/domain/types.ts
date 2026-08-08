export type MemberRole = 'owner' | 'member';
export type FocusCategory = 'study' | 'work' | 'reading' | 'exercise' | 'other';
export type FocusStatus = 'focusing' | 'paused' | 'completed' | 'discarded';
export type CompletionReason =
  'manual_end' | 'pause_timeout' | 'focus_limit' | 'member_disabled';

export interface TaskRevision {
  task_name: string;
  category: FocusCategory;
  changed_at: string;
}

export interface Membership {
  member_id: string;
  space_id: string;
  display_name: string;
  role: MemberRole;
  status: 'active' | 'disabled';
  joined_at?: string;
}

export interface SpaceSummary {
  id: string;
  name: string;
  timezone: string;
  member_limit: number;
  active_member_count?: number;
  daily_checkin_target_minutes: number;
  created_at?: string;
}

export interface FocusSession {
  session_id: string;
  space_id: string;
  member_id: string;
  task_name: string;
  category: FocusCategory;
  task_history: TaskRevision[];
  status: FocusStatus;
  started_at: string;
  timezone_snapshot: string;
  accumulated_focus_seconds: number;
  active_segment_started_at: string | null;
  paused_at: string | null;
  auto_settle_at: string | null;
  completed_at: string | null;
  completion_reason: CompletionReason | null;
  credited_focus_seconds: number | null;
  counts_toward_stats: boolean | null;
  connection?: {
    status: 'connected' | 'unconfirmed';
    last_seen_at: string;
    unconfirmed_connection_seconds?: number;
  };
}

export interface FocusingMember {
  member_id: string;
  display_name: string;
  session_id: string;
  task_name: string;
  category: FocusCategory;
  task_history: TaskRevision[];
  status: 'focusing';
  accumulated_focus_seconds: number;
  active_segment_started_at: string;
  timezone_snapshot: string;
  connection: { status: 'connected' | 'unconfirmed'; last_seen_at: string };
}

export interface HomeSnapshot {
  space: SpaceSummary & { active_member_count: number };
  me: {
    member_id: string;
    display_name: string;
    role: MemberRole;
    profile_timezone: string;
  };
  my_session: FocusSession | null;
  focusing_members: FocusingMember[];
  today: {
    local_date: string;
    credited_focus_seconds: number;
    checkin_target_seconds: number;
    checkin_completed: boolean;
    current_streak_days: number;
    goal_target_minutes: number;
    goal_source: 'space_default' | 'personal_default' | 'today_override';
    goal_locked: boolean;
    future_default_target_minutes: number;
  };
  active_goal_summary: Goal | null;
  unseen_achievement: Achievement | null;
  unseen_personal_achievement?: Achievement | null;
}

export interface StatsSummary {
  space_id: string;
  view: 'mine' | 'space';
  period: 'daily' | 'weekly' | 'monthly';
  timezone: string;
  period_start: string;
  period_end: string;
  credited_focus_seconds: number;
  valid_session_count: number;
  checkin_day_count: number;
  days: Array<{
    local_date: string;
    credited_focus_seconds: number;
    checkin_completed: boolean;
  }>;
}

export interface HistoryItem {
  session_id: string;
  member: { member_id: string; display_name: string };
  task_name: string;
  category: FocusCategory;
  started_at: string;
  completed_at: string;
  credited_focus_seconds: number;
  status: 'completed' | 'discarded';
  completion_reason: CompletionReason;
  counts_toward_stats: boolean;
  unconfirmed_connection_seconds: number;
}

export interface FocusSessionDetail {
  session: FocusSession;
  segments: Array<{ started_at: string; ended_at: string | null }>;
  connection_unconfirmed_intervals: Array<{
    started_at: string;
    ended_at: string | null;
    detected_from_last_seen_at: string;
  }>;
  settlement: {
    reason: CompletionReason;
    counts_toward_stats: boolean;
  };
}

export type GoalType =
  'group_total_minutes' | 'per_member_minutes' | 'shared_checkin_days';
export type PeriodType = 'daily' | 'weekly' | 'monthly';

export interface GoalProposal {
  proposal_id: string;
  proposer: { member_id: string; display_name: string };
  goal_type: GoalType;
  period_type: PeriodType;
  target_value: number;
  status: 'pending' | 'accepted' | 'rejected' | 'expired';
  created_at: string;
  expires_at: string;
  effective_period_start: string;
  required_vote_count: number;
  accepted_vote_count: number;
  my_vote: 'accepted' | 'rejected' | null;
}

export interface Goal {
  goal_id: string;
  goal_type: GoalType;
  period_type: PeriodType;
  target_value: number;
  status: 'scheduled' | 'active' | 'completed' | 'failed';
  starts_at: string;
  ends_at: string;
  progress: {
    credited_value: number | null;
    completed: boolean;
    members: Array<{
      member_id: string;
      display_name: string;
      credited_value: number | null;
      completed: boolean;
      completed_days?: number;
      required_days?: number;
      current_day_credited_minutes?: number;
    }> | null;
  };
}

export interface Achievement {
  achievement_id: string;
  achievement_type: string;
  tier?: 'bronze' | 'silver' | 'gold' | 'diamond';
  earned_at: string;
  metadata?: Record<string, string | number | boolean>;
  participants_recorded?: boolean;
  participants?: Array<{
    member_id: string;
    display_name: string;
    participation_days: number;
  }>;
  seen?: boolean;
  first_earned_at?: string;
  last_earned_at?: string;
  count?: number;
  events?: Array<{
    achievement_id?: string;
    earned_at: string;
    local_date?: string;
    source_space_id?: string;
    metadata?: Record<string, string | number | boolean>;
    participants?: Array<{
      member_id: string;
      display_name: string;
      participation_days: number;
    }>;
  }>;
}

export interface SpaceSettings {
  space: SpaceSummary;
  me: {
    member_id: string;
    display_name: string;
    role: MemberRole;
    profile_timezone: string;
  };
  members: Array<Membership & { joined_at: string }>;
  owner_actions: {
    can_copy_invite: boolean;
    can_rotate_invite: boolean;
    can_disable_members: boolean;
    can_update_space_name: boolean;
    can_increase_member_limit: boolean;
  };
}
