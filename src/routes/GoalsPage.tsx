import {
  useInfiniteQuery,
  useMutation,
  useQuery,
  useQueryClient,
} from '@tanstack/react-query';
import { useEffect, useState } from 'react';
import { useParams } from 'react-router-dom';
import type {
  Achievement,
  Goal,
  GoalProposal,
  GoalType,
  HomeSnapshot,
  PeriodType,
} from '../domain/types';
import { rpc } from '../lib/api';
import {
  formatLocalDateTime,
  goalTypeLabels,
  periodLabels,
} from '../lib/format';
import { useIntentKey } from '../hooks/useIntentKey';
import { useAutoAcknowledge } from '../hooks/useAutoAcknowledge';
import { AccessibleModal } from '../components/AccessibleModal';
import { EmptyState, ErrorState, PageLoader } from '../components/AsyncState';
import { Icon } from '../components/Icons';
import { AchievementIcon } from '../components/AchievementIcon';
import {
  achievementCondition,
  achievementDisplayDate,
  achievementSeries,
  achievementStages,
  achievementTitle,
  achievementTier,
  isAchievementUnlocked,
  isRepeatableAchievement,
  visibleAchievementEvents,
} from '../domain/achievementTier';
import { uniqueAchievementParticipantCount } from '../domain/achievementParticipants';
import { proposalSentence, proposedPeriodLabel } from '../lib/goalPreview';
import { loadResolvedGoalProposals } from '../lib/goalHistory';
import { assertRouteSpace } from '../lib/spaceBoundary';

interface GoalsSnapshot {
  space_id: string;
  active_goals: Goal[];
  scheduled_goals: Goal[];
  pending_proposals: GoalProposal[];
  history: Goal[];
  proposal_history?: GoalProposal[];
}

function GoalCard({ goal }: { goal: Goal }) {
  const credited = goal.progress.credited_value;
  const percent =
    credited === null
      ? null
      : Math.min(100, Math.round((credited / goal.target_value) * 100));
  const unit = goal.goal_type === 'shared_checkin_days' ? '天' : '分钟';
  const statusLabel =
    goal.status === 'scheduled'
      ? '即将生效'
      : goal.status === 'failed'
        ? '未达成'
        : goal.status === 'completed' || goal.progress.completed
          ? '已完成'
          : percent === null
            ? '按成员计算'
            : `${percent}%`;
  return (
    <article className={`goal-card goal-card--${goal.status}`}>
      <div className="goal-card__top">
        <span className="pill">{periodLabels[goal.period_type]}</span>
        <span>{statusLabel}</span>
      </div>
      <h3>{goalTypeLabels[goal.goal_type]}</h3>
      {credited === null ? (
        <p>
          每位成员每天至少完成 {goal.target_value} {unit}
        </p>
      ) : (
        <p>
          {credited} / {goal.target_value} {unit}
        </p>
      )}
      {percent !== null && (
        <progress
          className="progress-track"
          value={percent}
          max={100}
          aria-label={`目标完成进度 ${percent}%`}
        >
          {percent}%
        </progress>
      )}
      {goal.progress.members && (
        <div className="goal-members">
          {goal.progress.members.map((member) => (
            <div key={member.member_id}>
              <span>{member.display_name}</span>
              <span>
                {goal.goal_type === 'per_member_minutes' &&
                member.required_days !== undefined
                  ? `已达标 ${member.completed_days ?? 0} / ${member.required_days} 天 · 当天 ${member.current_day_credited_minutes ?? 0} / ${goal.target_value} 分钟`
                  : `${member.credited_value ?? 0} / ${goal.target_value} ${unit}`}{' '}
                {member.completed && <Icon name="check" />}
              </span>
            </div>
          ))}
        </div>
      )}
      <small>
        {formatLocalDateTime(goal.starts_at)} —{' '}
        {formatLocalDateTime(goal.ends_at)}
      </small>
    </article>
  );
}

function AchievementCard({ item }: { item: Achievement }) {
  const tier = achievementTier(item);
  const participants = item.participants ?? [];
  const eventGroups = visibleAchievementEvents(item).filter(
    (event) => event.participants?.length,
  );
  const canUseParticipantSnapshot =
    !isRepeatableAchievement(item) || eventGroups.length > 0;
  const participantCount = uniqueAchievementParticipantCount({
    ...item,
    participants: canUseParticipantSnapshot ? participants : [],
    events: eventGroups,
  });
  const participantText = eventGroups.length
    ? eventGroups
        .map(
          (event) =>
            `${formatLocalDateTime(event.earned_at)}：${event.participants!.map((participant) => participant.display_name).join('、')}`,
        )
        .join('\n')
    : canUseParticipantSnapshot
      ? item.participants_recorded
        ? participants
            .map((participant) =>
              participant.participation_days > 1
                ? `${participant.display_name}（${participant.participation_days} 天）`
                : participant.display_name,
            )
            .join('、')
        : '早期成就的参与成员记录暂缺'
      : '暂无可展示的解锁参与记录';
  return (
    <article
      className={`achievement-card achievement-card--${tier}${!item.seen ? ' achievement--new' : ''}`}
    >
      <span
        className={`achievement-card__icon achievement-card__icon--${tier}`}
      >
        <AchievementIcon item={item} />
      </span>
      <h3>{achievementTitle(item)}</h3>
      {achievementSeries(item) && (
        <small className="achievement-card__series">
          系列 · {achievementSeries(item)}
        </small>
      )}
      {achievementStages(item) && (
        <small className="achievement-card__earned-stages">
          已获得：{achievementStages(item)}
        </small>
      )}
      <p>{formatLocalDateTime(achievementDisplayDate(item))}</p>
      <button
        type="button"
        className="achievement-condition"
        aria-label={`达成条件：${achievementCondition(item)}`}
      >
        达成条件
        <span role="tooltip">{achievementCondition(item)}</span>
      </button>
      {!isPersonalAchievement(item.achievement_type) && (
        <button
          type="button"
          className="achievement-tooltip-trigger"
          aria-label={`一起达成的人：${participantText}`}
        >
          <Icon name="people" /> 一起达成的人（
          {participantCount || '—'}）
          <span role="tooltip">{participantText}</span>
        </button>
      )}
      {!item.seen && <small>新成就，已自动记录为已读</small>}
    </article>
  );
}

export function GoalsPage() {
  const { spaceId = '' } = useParams();
  const queryClient = useQueryClient();
  const proposalIntent = useIntentKey();
  const voteIntent = useIntentKey();
  const seenIntent = useIntentKey();
  const [showForm, setShowForm] = useState(false);
  const [formStep, setFormStep] = useState<1 | 2 | 3>(1);
  const [rejectProposal, setRejectProposal] = useState<GoalProposal | null>(
    null,
  );
  const [resolvedProposals, setResolvedProposals] = useState<GoalProposal[]>(
    [],
  );
  const [goalType, setGoalType] = useState<GoalType>('group_total_minutes');
  const [periodType, setPeriodType] = useState<PeriodType>('weekly');
  const [target, setTarget] = useState(1200);
  const [achievementTab, setAchievementTab] = useState<'personal' | 'shared'>(
    'personal',
  );
  const targetMax =
    goalType === 'group_total_minutes'
      ? 1_000_000
      : goalType === 'per_member_minutes'
        ? 720
        : periodType === 'daily'
          ? 1
          : periodType === 'weekly'
            ? 7
            : 31;
  const goals = useQuery({
    queryKey: ['goals', spaceId],
    queryFn: async () => {
      const result = await rpc<GoalsSnapshot>('get_goals_snapshot', {
        space_id: spaceId,
      });
      assertRouteSpace(spaceId, result.data.space_id, 'goals_snapshot_space');
      return result;
    },
    refetchInterval: 60_000,
  });
  const home = useQuery({
    queryKey: ['goal-form-context', spaceId],
    queryFn: async () => {
      const result = await rpc<HomeSnapshot>('get_home_snapshot', {
        space_id: spaceId,
      });
      assertRouteSpace(spaceId, result.data.space.id, 'goal_home_space');
      return result;
    },
  });
  const achievements = useInfiniteQuery({
    queryKey: ['achievements', spaceId],
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      const result = await rpc<{
        space_id: string;
        items: Achievement[];
        next_cursor: string | null;
      }>('list_achievements', {
        space_id: spaceId,
        limit: 30,
        cursor: pageParam,
      });
      assertRouteSpace(
        spaceId,
        result.data.space_id,
        'goal_achievements_space',
      );
      return result;
    },
    getNextPageParam: (last) => last.data.next_cursor ?? undefined,
    refetchInterval: 60_000,
  });
  const personalAchievements = useInfiniteQuery({
    queryKey: ['personal-achievements', spaceId],
    initialPageParam: null as string | null,
    queryFn: async ({ pageParam }) => {
      const result = await rpc<{
        space_id: string;
        items: Achievement[];
        next_cursor: string | null;
      }>('list_personal_achievements', {
        space_id: spaceId,
        limit: 30,
        cursor: pageParam,
      });
      assertRouteSpace(
        spaceId,
        result.data.space_id,
        'goal_personal_achievements_space',
      );
      return result;
    },
    getNextPageParam: (last) => last.data.next_cursor ?? undefined,
    refetchInterval: 60_000,
  });
  const resolvedHistory = useQuery({
    queryKey: ['goal-proposal-history', spaceId],
    queryFn: () => loadResolvedGoalProposals(spaceId),
    refetchInterval: 60_000,
  });
  const refresh = () => {
    void queryClient.invalidateQueries({ queryKey: ['goals', spaceId] });
    void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
    void queryClient.invalidateQueries({
      queryKey: ['goal-proposal-history', spaceId],
    });
    void queryClient.invalidateQueries({
      queryKey: ['nav-notifications', spaceId],
    });
  };
  const propose = useMutation({
    mutationFn: () => {
      const signature = `${spaceId}:${goalType}:${periodType}:${target}`;
      return rpc('propose_goal', {
        space_id: spaceId,
        goal_type: goalType,
        period_type: periodType,
        target_value: target,
        idempotency_key: proposalIntent.get(signature),
      });
    },
    onSuccess: () => {
      proposalIntent.clear();
      setShowForm(false);
      setFormStep(1);
      refresh();
    },
  });
  const vote = useMutation({
    mutationFn: ({
      proposalId,
      value,
    }: {
      proposalId: string;
      value: 'accepted' | 'rejected';
    }) =>
      rpc<{ proposal: GoalProposal }>('vote_goal_proposal', {
        proposal_id: proposalId,
        vote: value,
        idempotency_key: voteIntent.get(`${proposalId}:${value}`),
      }),
    onSuccess: ({ data }: { data: { proposal: GoalProposal } }) => {
      voteIntent.clear();
      if (
        data.proposal.status === 'rejected' ||
        data.proposal.status === 'expired'
      )
        setResolvedProposals((items) => [
          data.proposal,
          ...items.filter(
            (item) => item.proposal_id !== data.proposal.proposal_id,
          ),
        ]);
      setRejectProposal(null);
      refresh();
    },
  });
  const markSeen = useMutation({
    mutationFn: (achievementId: string) =>
      rpc('mark_achievement_seen', {
        achievement_id: achievementId,
        idempotency_key: seenIntent.get(achievementId),
      }),
    onSuccess: () => {
      seenIntent.clear();
      void queryClient.invalidateQueries({
        queryKey: ['achievements', spaceId],
      });
      void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
    },
    retry: 2,
  });
  useEffect(() => {
    const loaded =
      achievementTab === 'personal'
        ? personalAchievements.isSuccess
        : achievements.isSuccess;
    if (!loaded) return;
    void rpc('mark_achievement_tab_seen', {
      space_id: spaceId,
      tab: achievementTab,
    }).then(() =>
      queryClient.invalidateQueries({
        queryKey: ['nav-notifications', spaceId],
      }),
    );
  }, [
    achievementTab,
    achievements.isSuccess,
    personalAchievements.isSuccess,
    queryClient,
    spaceId,
  ]);
  const snapshot = goals.data?.data;
  const hasOpenGoal = Boolean(
    snapshot?.pending_proposals.length ||
    snapshot?.scheduled_goals.length ||
    snapshot?.active_goals.length,
  );
  const achievementItems =
    achievements.data?.pages
      .flatMap((page) => page.data.items)
      .filter(isAchievementUnlocked) ?? [];
  const personalAchievementItems =
    personalAchievements.data?.pages
      .flatMap((page) => page.data.items)
      .filter(isAchievementUnlocked) ?? [];
  const unseenAchievementId = achievementItems.find(
    (item) => !item.seen,
  )?.achievement_id;
  useAutoAcknowledge(unseenAchievementId, (achievementId) => {
    markSeen.mutate(achievementId);
  });
  const proposalHistory = [
    ...resolvedProposals,
    ...(resolvedHistory.data ?? []),
    ...(snapshot?.proposal_history ?? []),
  ].filter(
    (proposal, index, items) =>
      items.findIndex((item) => item.proposal_id === proposal.proposal_id) ===
      index,
  );
  return (
    <div className="page goals-page">
      <header className="page-header">
        <div>
          <p className="eyebrow">一起走得更远</p>
          <h1>共同目标</h1>
        </div>
        <button
          className="button button--secondary button--compact"
          disabled={hasOpenGoal}
          onClick={() => {
            setFormStep(1);
            setShowForm(true);
          }}
        >
          发起提案
        </button>
      </header>
      {goals.isLoading ? (
        <PageLoader />
      ) : !snapshot ? (
        <ErrorState onRetry={() => void goals.refetch()} />
      ) : (
        <>
          {goals.error && (
            <div className="inline-notice inline-notice--warning" role="status">
              目标状态暂时没有更新，正在显示上次成功加载的数据。
              <button type="button" onClick={() => void goals.refetch()}>
                重新加载
              </button>
            </div>
          )}
          <section className="section">
            <div className="section-heading">
              <h2>进行中</h2>
              <span>{snapshot.active_goals.length}</span>
            </div>
            {snapshot.active_goals.length ? (
              snapshot.active_goals.map((goal) => (
                <GoalCard key={goal.goal_id} goal={goal} />
              ))
            ) : (
              <EmptyState icon="target" title="还没有生效目标">
                <p>共同目标需要所有成员投票同意，并从下一个完整周期开始。</p>
              </EmptyState>
            )}
          </section>
          {snapshot.scheduled_goals.length > 0 && (
            <section className="section">
              <div className="section-heading">
                <h2>即将开始</h2>
              </div>
              {snapshot.scheduled_goals.map((goal) => (
                <GoalCard key={goal.goal_id} goal={goal} />
              ))}
            </section>
          )}
          <section className="section">
            <div className="section-heading">
              <h2>等待投票</h2>
              <span>48 小时有效</span>
            </div>
            {snapshot.pending_proposals.length ? (
              <div className="proposal-list">
                {snapshot.pending_proposals.map((proposal) => (
                  <article className="proposal-card" key={proposal.proposal_id}>
                    <p>
                      <strong>{proposal.proposer.display_name}</strong> 发起
                    </p>
                    <h3>
                      {periodLabels[proposal.period_type]} ·{' '}
                      {goalTypeLabels[proposal.goal_type]}
                    </h3>
                    <p>
                      {proposalSentence(
                        proposal.goal_type,
                        proposal.period_type,
                        proposal.target_value,
                      )}
                    </p>
                    <small>
                      {proposal.accepted_vote_count} /{' '}
                      {proposal.required_vote_count} 人已同意 ·{' '}
                      {Math.max(
                        0,
                        Math.ceil(
                          (Date.parse(proposal.expires_at) -
                            Date.parse(goals.data?.serverNow ?? '')) /
                            3_600_000,
                        ),
                      )}{' '}
                      小时后过期 · {formatLocalDateTime(proposal.expires_at)}
                    </small>
                    {proposal.my_vote ? (
                      <span
                        className={`vote-status vote-status--${proposal.my_vote}`}
                      >
                        <Icon name="check" />
                        你已{proposal.my_vote === 'accepted' ? '同意' : '拒绝'}
                      </span>
                    ) : (
                      <div className="proposal-card__actions">
                        <button
                          className="button button--secondary"
                          disabled={vote.isPending}
                          onClick={() => setRejectProposal(proposal)}
                        >
                          拒绝
                        </button>
                        <button
                          className="button button--primary"
                          disabled={vote.isPending}
                          onClick={() =>
                            vote.mutate({
                              proposalId: proposal.proposal_id,
                              value: 'accepted',
                            })
                          }
                        >
                          同意
                        </button>
                      </div>
                    )}
                  </article>
                ))}
              </div>
            ) : (
              <p className="quiet-copy">没有等待投票的提案。</p>
            )}
          </section>
          {snapshot.history.length > 0 && (
            <section className="section">
              <div className="section-heading">
                <h2>过往目标</h2>
              </div>
              {snapshot.history.map((goal) => (
                <GoalCard key={goal.goal_id} goal={goal} />
              ))}
            </section>
          )}
          {proposalHistory.length > 0 && (
            <section className="section">
              <div className="section-heading">
                <h2>已结束提案</h2>
              </div>
              <div className="proposal-list">
                {proposalHistory.map((proposal) => (
                  <article className="proposal-card" key={proposal.proposal_id}>
                    <span className="pill">
                      {proposal.status === 'rejected' ? '已拒绝' : '已过期'}
                    </span>
                    <h3>
                      {proposalSentence(
                        proposal.goal_type,
                        proposal.period_type,
                        proposal.target_value,
                      )}
                    </h3>
                    <small>发起人：{proposal.proposer.display_name}</small>
                  </article>
                ))}
              </div>
            </section>
          )}
          {resolvedHistory.error && (
            <ErrorState
              title="无法加载已结束提案"
              message="被拒绝和已过期的提案尚未完整加载。"
              onRetry={() => void resolvedHistory.refetch()}
            />
          )}
          <section className="section achievement-section">
            <div className="section-heading">
              <h2>成就</h2>
              <span>
                {achievementTab === 'personal'
                  ? personalAchievementItems.length
                  : achievementItems.length}
              </span>
            </div>
            <div
              className="achievement-tabs"
              role="tablist"
              aria-label="成就类型"
            >
              <button
                type="button"
                role="tab"
                aria-selected={achievementTab === 'personal'}
                className={achievementTab === 'personal' ? 'is-active' : ''}
                onClick={() => setAchievementTab('personal')}
              >
                个人成就
              </button>
              <button
                type="button"
                role="tab"
                aria-selected={achievementTab === 'shared'}
                className={achievementTab === 'shared' ? 'is-active' : ''}
                onClick={() => setAchievementTab('shared')}
              >
                共同成就
              </button>
            </div>
            {achievementTab === 'shared' &&
              achievements.error &&
              achievementItems.length > 0 && (
                <div
                  className="inline-notice inline-notice--warning"
                  role="status"
                >
                  新的成就暂时没有加载，当前记录仍可查看。
                  <button
                    type="button"
                    onClick={() => void achievements.refetch()}
                  >
                    重新加载
                  </button>
                </div>
              )}
            {achievementTab === 'personal' ? (
              personalAchievementItems.length ? (
                <>
                  <div className="achievement-grid">
                    {personalAchievementItems.map((item) => (
                      <AchievementCard item={item} key={item.achievement_id} />
                    ))}
                  </div>
                  {personalAchievements.hasNextPage && (
                    <button
                      className="button button--secondary button--full"
                      disabled={personalAchievements.isFetchingNextPage}
                      onClick={() => void personalAchievements.fetchNextPage()}
                    >
                      {personalAchievements.isFetchingNextPage
                        ? '正在加载…'
                        : '加载更多成就'}
                    </button>
                  )}
                </>
              ) : personalAchievements.error ? (
                <ErrorState
                  title="无法加载个人成就"
                  message="个人成就尚未完整加载。"
                  onRetry={() => void personalAchievements.refetch()}
                />
              ) : personalAchievements.isLoading ? (
                <PageLoader />
              ) : (
                <p className="quiet-copy">
                  完成符合条件的专注后，个人成就会出现在这里。
                </p>
              )
            ) : achievementItems.length ? (
              <>
                <div className="achievement-grid">
                  {achievementItems.map((item) => (
                    <AchievementCard item={item} key={item.achievement_id} />
                  ))}
                </div>
                {achievements.hasNextPage && (
                  <button
                    className="button button--secondary button--full"
                    disabled={achievements.isFetchingNextPage}
                    onClick={() => void achievements.fetchNextPage()}
                  >
                    {achievements.isFetchingNextPage
                      ? '正在加载…'
                      : '加载更多成就'}
                  </button>
                )}
              </>
            ) : achievements.error ? (
              <ErrorState
                title="无法加载成就记录"
                message="共同成就尚未完整加载。"
                onRetry={() => void achievements.refetch()}
              />
            ) : (
              <p className="quiet-copy">
                一起亮灯、连续相伴和完成目标后，成就会出现在这里。
              </p>
            )}
          </section>
        </>
      )}
      {(propose.error || vote.error || markSeen.error) && (
        <div className="inline-notice inline-notice--error" role="alert">
          {(propose.error ?? vote.error ?? markSeen.error)?.message}
        </div>
      )}
      {showForm && (
        <AccessibleModal
          titleId="proposal-title"
          onClose={() => {
            if (!propose.isPending) {
              setShowForm(false);
              setFormStep(1);
            }
          }}
          closeOnBackdrop={!propose.isPending}
        >
          <span className="drawer__handle" />
          <h2 id="proposal-title">发起共同目标 · {formStep}/3</h2>
          {formStep === 1 && (
            <label className="field">
              <span>目标类型</span>
              <select
                autoFocus
                value={goalType}
                onChange={(e) => {
                  const type = e.target.value as GoalType;
                  setGoalType(type);
                  setTarget(
                    type === 'shared_checkin_days'
                      ? periodType === 'daily'
                        ? 1
                        : 3
                      : type === 'per_member_minutes'
                        ? 180
                        : 1200,
                  );
                }}
              >
                {Object.entries(goalTypeLabels).map(([value, label]) => (
                  <option key={value} value={value}>
                    {label}
                  </option>
                ))}
              </select>
            </label>
          )}
          {formStep === 2 && (
            <>
              <label className="field">
                <span>周期</span>
                <select
                  value={periodType}
                  onChange={(e) => {
                    const period = e.target.value as PeriodType;
                    setPeriodType(period);
                    if (goalType === 'shared_checkin_days') {
                      setTarget((current) =>
                        period === 'daily'
                          ? 1
                          : Math.min(current, period === 'weekly' ? 7 : 31),
                      );
                    }
                  }}
                >
                  {Object.entries(periodLabels).map(([value, label]) => (
                    <option key={value} value={value}>
                      {label}
                    </option>
                  ))}
                </select>
              </label>
              <label className="field">
                <span>
                  {goalType === 'per_member_minutes' ? '每日' : ''}目标值（
                  {goalType === 'shared_checkin_days' ? '天' : '分钟'}）
                </span>
                <input
                  type="number"
                  min="1"
                  max={targetMax}
                  step="1"
                  value={target}
                  onChange={(e) => setTarget(Number(e.target.value))}
                />
                <small className="field-hint">
                  {proposalSentence(goalType, periodType, target)}
                </small>
              </label>
            </>
          )}
          {formStep === 3 && home.isLoading ? (
            <PageLoader />
          ) : formStep === 3 && (home.error || !home.data) ? (
            <ErrorState
              title="无法确认提案生效信息"
              message="需要先取得房间时区、成员数与服务端时间。"
              onRetry={() => void home.refetch()}
            />
          ) : formStep === 3 && home.data ? (
            <section className="proposal-preview" aria-label="提案预览">
              <p className="eyebrow">完整提案</p>
              <h3>{proposalSentence(goalType, periodType, target)}</h3>
              <dl className="detail-list">
                <div>
                  <dt>生效周期</dt>
                  <dd>
                    {proposedPeriodLabel(
                      periodType,
                      home.data.data.space.timezone,
                      new Date(home.data.serverNow),
                    )}
                  </dd>
                </div>
                <div>
                  <dt>需要同意</dt>
                  <dd>{home.data.data.space.active_member_count} 人</dd>
                </div>
                <div>
                  <dt>投票截止</dt>
                  <dd>
                    {formatLocalDateTime(
                      new Date(
                        Date.parse(home.data.serverNow) + 48 * 60 * 60 * 1000,
                      ).toISOString(),
                      home.data.data.space.timezone,
                    )}
                  </dd>
                </div>
              </dl>
              <p>提交后不可修改；全员同意后的次日 00:00 生效。</p>
            </section>
          ) : null}
          <div className="dialog__actions">
            {formStep > 1 && (
              <button
                className="button button--secondary"
                disabled={propose.isPending}
                onClick={() => setFormStep((formStep - 1) as 1 | 2)}
              >
                上一步
              </button>
            )}
            {formStep < 3 ? (
              <button
                className="button button--primary"
                disabled={
                  formStep === 2 &&
                  (target < 1 ||
                    target > targetMax ||
                    !Number.isInteger(target))
                }
                onClick={() => setFormStep((formStep + 1) as 2 | 3)}
              >
                下一步
              </button>
            ) : (
              <button
                className="button button--primary"
                disabled={
                  propose.isPending ||
                  target < 1 ||
                  target > targetMax ||
                  !Number.isInteger(target) ||
                  !home.data
                }
                onClick={() => propose.mutate()}
              >
                {propose.isPending ? '正在提交…' : '发起并投同意票'}
              </button>
            )}
          </div>
          <button
            className="button button--text button--full"
            disabled={propose.isPending}
            onClick={() => {
              setShowForm(false);
              setFormStep(1);
            }}
          >
            取消
          </button>
        </AccessibleModal>
      )}
      {rejectProposal && (
        <AccessibleModal
          kind="dialog"
          titleId="reject-title"
          onClose={() => {
            if (!vote.isPending) setRejectProposal(null);
          }}
          closeOnBackdrop={!vote.isPending}
        >
          <h2 id="reject-title">确认拒绝这个提案？</h2>
          <p>
            {proposalSentence(
              rejectProposal.goal_type,
              rejectProposal.period_type,
              rejectProposal.target_value,
            )}
          </p>
          <p>拒绝票提交后不可更改，提案会立即结束。</p>
          <div className="dialog__actions">
            <button
              className="button button--secondary"
              disabled={vote.isPending}
              onClick={() => setRejectProposal(null)}
            >
              取消
            </button>
            <button
              className="button button--danger"
              disabled={vote.isPending}
              onClick={() =>
                vote.mutate({
                  proposalId: rejectProposal.proposal_id,
                  value: 'rejected',
                })
              }
            >
              {vote.isPending ? '正在提交…' : '确认拒绝'}
            </button>
          </div>
        </AccessibleModal>
      )}
    </div>
  );
}

const personalAchievementTypes = new Set([
  'night_owl',
  'dawn_walker',
  'solo_focus',
  'unbroken_focus',
  'double_focus',
  'triple_focus',
  'three_categories',
  'promise_keeper',
  'return_after_break',
]);

function isPersonalAchievement(type: string) {
  return personalAchievementTypes.has(type);
}
