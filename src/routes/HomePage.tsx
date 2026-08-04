import { useMutation, useQuery, useQueryClient } from '@tanstack/react-query';
import { useEffect, useRef, useState } from 'react';
import { Link, useLocation, useParams } from 'react-router-dom';
import type {
  FocusCategory,
  FocusSession,
  HomeSnapshot,
  TaskRevision,
} from '../domain/types';
import { ApiError, rpc } from '../lib/api';
import {
  categoryLabels,
  formatDuration,
  formatLocalDateTime,
} from '../lib/format';
import { calculateFocusSeconds, useServerClock } from '../hooks/useServerClock';
import {
  type ConnectionState,
  useRoomRealtime,
} from '../hooks/useRoomRealtime';
import { EmptyState, ErrorState, PageLoader } from '../components/AsyncState';
import { Icon } from '../components/Icons';
import { Lamp } from '../components/Lamp';
import { AccessibleModal } from '../components/AccessibleModal';
import { useIntentKey } from '../hooks/useIntentKey';
import { assertRouteSpace } from '../lib/spaceBoundary';
import { useAutoAcknowledge } from '../hooks/useAutoAcknowledge';
import {
  applyPersonalDailyGoal,
  type PersonalDailyGoalResult,
} from '../lib/personalDailyGoal';

const connectionCopy: Partial<Record<ConnectionState, string>> = {
  realtime_degraded: '实时更新暂时中断，正在重连',
  unconfirmed: '连接状态不可确认，计时仍在服务端继续',
  offline: '当前离线，计时仍在服务端继续',
  reconnecting: '正在同步最新状态…',
  conflict: '状态已在另一个页面更新，正在核对服务器结果',
};

const focusConflictCodes = new Set([
  'SESSION_ALREADY_ACTIVE',
  'SESSION_NOT_FOCUSING',
  'SESSION_NOT_PAUSED',
  'SESSION_NOT_FOUND',
  'IDEMPOTENCY_KEY_REUSED',
]);

interface SnapshotResult {
  snapshot: HomeSnapshot;
  serverNow: string;
  receivedAt: number;
}

async function getSnapshot(spaceId: string): Promise<SnapshotResult> {
  const result = await rpc<HomeSnapshot>('get_home_snapshot', {
    space_id: spaceId,
  });
  assertRouteSpace(spaceId, result.data.space.id, 'home_snapshot_space');
  return {
    snapshot: result.data,
    serverNow: result.serverNow,
    receivedAt: Date.now(),
  };
}

function Summary({
  data,
  onEdit,
}: {
  data: HomeSnapshot['today'];
  onEdit: () => void;
}) {
  const remaining = Math.max(
    0,
    data.checkin_target_seconds - data.credited_focus_seconds,
  );
  return (
    <div className="summary-card-wrap">
      <section
        className={`summary-card${data.checkin_completed ? ' summary-card--complete' : ''}`}
        aria-label="今日专注摘要"
      >
        <div>
          <small>今天</small>
          <strong>{formatDuration(data.credited_focus_seconds)}</strong>
        </div>
        <div>
          <small>
            {data.checkin_completed ? '个人目标已完成' : '距我的目标'}
          </small>
          <strong>
            {data.checkin_completed ? '完成' : formatDuration(remaining)}
          </strong>
        </div>
        <div>
          <small>连续</small>
          <strong>{data.current_streak_days} 天</strong>
        </div>
        <progress
          className="summary-card__progress"
          max={data.checkin_target_seconds}
          value={Math.min(
            data.checkin_target_seconds,
            data.credited_focus_seconds,
          )}
          aria-label="今日个人目标进度"
        />
      </section>
      <button className="summary-card__edit" type="button" onClick={onEdit}>
        修改我的目标 · {data.goal_target_minutes} 分钟
      </button>
    </div>
  );
}

export function DailyGoalDrawer({
  today,
  onClose,
  onSave,
  pending,
  error,
}: {
  today: HomeSnapshot['today'];
  onClose: () => void;
  onSave: (scope: 'today' | 'future_default', targetMinutes: number) => void;
  pending: boolean;
  error?: string;
}) {
  const [scope, setScope] = useState<'today' | 'future_default'>(
    today.goal_locked ? 'future_default' : 'today',
  );
  const [target, setTarget] = useState(
    today.goal_locked
      ? today.future_default_target_minutes
      : today.goal_target_minutes,
  );
  const valid = Number.isInteger(target) && target >= 30 && target <= 720;
  return (
    <AccessibleModal
      titleId="daily-goal-title"
      onClose={onClose}
      closeOnBackdrop={!pending}
    >
      <h2 id="daily-goal-title">修改我的每日专注目标</h2>
      <p>目标至少为30分钟。今天开始专注后，今日目标会锁定。</p>
      <label className="field">
        <span>目标时长（分钟）</span>
        <input
          data-autofocus
          type="number"
          min={30}
          max={720}
          step={5}
          value={target}
          onChange={(event) => setTarget(Number(event.target.value))}
        />
      </label>
      <fieldset className="goal-scope-picker">
        <legend>应用范围</legend>
        <label>
          <input
            type="radio"
            name="daily-goal-scope"
            checked={scope === 'today'}
            disabled={today.goal_locked}
            onChange={() => setScope('today')}
          />
          <span>仅修改今天</span>
        </label>
        <label>
          <input
            type="radio"
            name="daily-goal-scope"
            checked={scope === 'future_default'}
            onChange={() => setScope('future_default')}
          />
          <span>从明天起每天重复</span>
        </label>
      </fieldset>
      {today.goal_locked && (
        <p className="field-hint">
          今天已经开始过专注，只能修改明天起的默认目标。
        </p>
      )}
      {!valid && <p className="field-error">请输入30–720之间的整数分钟。</p>}
      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}
      <button
        className="button button--primary button--full"
        type="button"
        disabled={!valid || pending}
        onClick={() => onSave(scope, target)}
      >
        {pending ? '正在保存…' : '保存目标'}
      </button>
      <button
        className="button button--text button--full"
        type="button"
        disabled={pending}
        onClick={onClose}
      >
        取消
      </button>
    </AccessibleModal>
  );
}

function StartDrawer({
  onClose,
  onStart,
  pending,
}: {
  onClose: () => void;
  onStart: (task: string, category: FocusCategory) => void;
  pending: boolean;
}) {
  const [task, setTask] = useState('');
  const [category, setCategory] = useState<FocusCategory>('study');
  const trimmed = task.trim();
  return (
    <AccessibleModal
      titleId="start-title"
      onClose={onClose}
      closeOnBackdrop={!pending}
    >
      <span className="drawer__handle" />
      <h2 id="start-title">这次想专注什么？</h2>
      <p>写下一件事，让这一盏灯有清晰的方向。</p>
      <label className="field">
        <span>任务名称</span>
        <textarea
          data-autofocus
          maxLength={80}
          rows={3}
          value={task}
          onChange={(e) => setTask(e.target.value)}
        />
        <small
          className={
            task.length > 72 ? 'field-hint field-hint--warning' : 'field-hint'
          }
        >
          {80 - task.length} 字可用
        </small>
      </label>
      <fieldset className="category-picker">
        <legend>分类</legend>
        {(Object.entries(categoryLabels) as Array<[FocusCategory, string]>).map(
          ([value, label]) => (
            <label key={value}>
              <input
                type="radio"
                name="category"
                value={value}
                checked={category === value}
                onChange={() => setCategory(value)}
              />
              <span>{label}</span>
            </label>
          ),
        )}
      </fieldset>
      {!trimmed && task.length > 0 && (
        <p className="field-error">写下这次要做的事情。</p>
      )}
      <button
        className="button button--primary button--full"
        type="button"
        disabled={!trimmed || pending}
        onClick={() => onStart(trimmed, category)}
      >
        {pending ? '正在点亮…' : '点亮台灯'}
      </button>
      <button
        className="button button--text button--full"
        type="button"
        disabled={pending}
        onClick={onClose}
      >
        取消
      </button>
    </AccessibleModal>
  );
}

export function EditTaskDrawer({
  session,
  onClose,
  onSave,
  pending,
}: {
  session: FocusSession;
  onClose: () => void;
  onSave: (task: string, category: FocusCategory) => void;
  pending: boolean;
}) {
  const [task, setTask] = useState(session.task_name);
  const [category, setCategory] = useState<FocusCategory>(session.category);
  const trimmed = task.trim();
  const unchanged =
    trimmed === session.task_name && category === session.category;
  return (
    <AccessibleModal
      titleId="edit-task-title"
      onClose={onClose}
      closeOnBackdrop={!pending}
    >
      <span className="drawer__handle" />
      <h2 id="edit-task-title">修改当前任务</h2>
      <p>修改后，友间成员会看到最新版和可展开的旧版本。</p>
      <label className="field">
        <span>任务名称</span>
        <textarea
          data-autofocus
          maxLength={80}
          rows={3}
          value={task}
          onChange={(event) => setTask(event.target.value)}
        />
        <small className="field-hint">{80 - task.length} 字可用</small>
      </label>
      <fieldset className="category-picker">
        <legend>分类</legend>
        {(Object.entries(categoryLabels) as Array<[FocusCategory, string]>).map(
          ([value, label]) => (
            <label key={value}>
              <input
                type="radio"
                name="edit-category"
                value={value}
                checked={category === value}
                onChange={() => setCategory(value)}
              />
              <span>{label}</span>
            </label>
          ),
        )}
      </fieldset>
      {!trimmed && task.length > 0 && (
        <p className="field-error">写下这次要做的事情。</p>
      )}
      <button
        className="button button--primary button--full"
        type="button"
        disabled={!trimmed || unchanged || pending}
        onClick={() => onSave(trimmed, category)}
      >
        {pending ? '正在同步…' : '保存修改'}
      </button>
      <button
        className="button button--text button--full"
        type="button"
        disabled={pending}
        onClick={onClose}
      >
        取消
      </button>
    </AccessibleModal>
  );
}

export function TaskHistory({ history }: { history: TaskRevision[] }) {
  const [expanded, setExpanded] = useState(false);
  if (!history.length) return null;
  return (
    <div className="task-history">
      <button
        className="task-history__toggle"
        type="button"
        aria-expanded={expanded}
        onClick={() => setExpanded((value) => !value)}
      >
        已修改 · {expanded ? '收起旧任务' : `查看旧任务 (${history.length})`}
      </button>
      {expanded && (
        <ol className="task-history__list">
          {history.map((revision, index) => (
            <li key={`${revision.changed_at}:${index}`}>
              <span>{revision.task_name}</span>
              <small>
                {categoryLabels[revision.category]} · 修改于{' '}
                {formatLocalDateTime(revision.changed_at)}
              </small>
            </li>
          ))}
        </ol>
      )}
    </div>
  );
}

function SettledNotice({
  session,
  onDismiss,
}: {
  session: FocusSession;
  onDismiss: () => void;
}) {
  const reason = session.completion_reason;
  const copy =
    reason === 'pause_timeout'
      ? '因暂停超过 15 分钟，本次已自动结束。'
      : reason === 'focus_limit'
        ? '本次已达到 6 小时上限并自动结束。长时间专注后请适当休息。'
        : session.status === 'discarded'
          ? '本次不足 5 分钟，记录已保留，但不会计入统计和打卡。'
          : '这一段专注已经完成。';
  return (
    <section className="result-card" aria-live="polite">
      <span className="result-card__icon">
        <Icon name={session.status === 'discarded' ? 'clock' : 'check'} />
      </span>
      <h2>{session.status === 'discarded' ? '这一小段已记录' : '专注完成'}</h2>
      <p>{copy}</p>
      <strong>{formatDuration(session.credited_focus_seconds ?? 0)}</strong>
      <button className="button button--primary" onClick={onDismiss}>
        再来一段
      </button>
      <Link className="button button--text" to="stats">
        查看记录
      </Link>
    </section>
  );
}

function FocusPanel({
  session,
  now,
  connection,
  onPause,
  onResume,
  onEnd,
  onEdit,
  onDismiss,
  pending,
}: {
  session: FocusSession | null;
  now: number;
  connection: ConnectionState;
  onPause: () => void;
  onResume: () => void;
  onEnd: () => void;
  onEdit: () => void;
  onDismiss: () => void;
  pending: boolean;
}) {
  const [drawer, setDrawer] = useState(false);
  if (!session)
    return (
      <>
        <section className="focus-panel focus-panel--idle">
          <Lamp />
          <h2>留一段完整的时间给自己</h2>
          <p>准备好后，点亮台灯开始专注。</p>
          <button
            className="button button--primary button--wide"
            onClick={() => setDrawer(true)}
          >
            开始专注
          </button>
        </section>
        {drawer && (
          <StartDrawer
            pending={false}
            onClose={() => setDrawer(false)}
            onStart={() => undefined}
          />
        )}
      </>
    );
  const seconds = calculateFocusSeconds(session, now);
  if (session.status === 'completed' || session.status === 'discarded')
    return <SettledNotice session={session} onDismiss={onDismiss} />;
  const authorityPending =
    connection === 'reconnecting' || connection === 'conflict';
  if (session.status === 'paused') {
    const countdown = Math.max(
      0,
      Math.ceil((Date.parse(session.auto_settle_at ?? '') - now) / 1000),
    );
    return (
      <section className="focus-panel focus-panel--paused">
        <div className="pause-stage">
          <Lamp state="paused" />
          <p className="eyebrow">暂时离开</p>
          <h2>{session.task_name}</h2>
          <p>{categoryLabels[session.category]}</p>
          <TaskHistory history={session.task_history ?? []} />
          <button
            className="button button--text task-edit-button"
            type="button"
            disabled={pending || authorityPending || countdown === 0}
            onClick={onEdit}
          >
            修改任务
          </button>
          <strong className="timer">{formatDuration(seconds, true)}</strong>
          <hr />
          <p
            className={
              countdown <= 60 ? 'countdown countdown--warning' : 'countdown'
            }
          >
            {countdown > 0
              ? `${String(Math.floor(countdown / 60)).padStart(2, '0')}:${String(countdown % 60).padStart(2, '0')} 后自动结束`
              : '正在等待服务器确认'}
          </p>
          <button
            className="button button--pause button--wide"
            disabled={pending || authorityPending || countdown === 0}
            onClick={onResume}
          >
            {pending ? '正在同步…' : '继续专注'}
          </button>
        </div>
        <button
          className="button button--text"
          disabled={pending || authorityPending}
          onClick={onEnd}
        >
          结束本次
        </button>
      </section>
    );
  }
  return (
    <section className="focus-panel focus-panel--active">
      <Lamp state="focusing" />
      <p className="eyebrow">灯已点亮</p>
      <h2>{session.task_name}</h2>
      <p>{categoryLabels[session.category]}</p>
      <TaskHistory history={session.task_history ?? []} />
      <button
        className="button button--text task-edit-button"
        type="button"
        disabled={pending || authorityPending}
        onClick={onEdit}
      >
        修改任务
      </button>
      <strong className="timer">{formatDuration(seconds, true)}</strong>
      {session.auto_settle_at &&
        Date.parse(session.auto_settle_at) - now <= 30 * 60 * 1000 && (
          <p className="limit-note">
            距离 6 小时上限还有{' '}
            {formatDuration((Date.parse(session.auto_settle_at) - now) / 1000)}
          </p>
        )}
      <button
        className="button button--primary button--wide"
        disabled={pending || authorityPending}
        onClick={onPause}
      >
        {pending ? '正在暂停…' : '暂停'}
      </button>
      <button
        className="button button--text"
        disabled={pending || authorityPending}
        onClick={onEnd}
      >
        结束本次
      </button>
    </section>
  );
}

export function HomePage() {
  const { spaceId = '' } = useParams();
  const location = useLocation();
  const queryClient = useQueryClient();
  const query = useQuery({
    queryKey: ['home', spaceId],
    queryFn: () => getSnapshot(spaceId),
    refetchInterval: 60_000,
  });
  const now = useServerClock(query.data?.serverNow, query.data?.receivedAt);
  const [drawer, setDrawer] = useState(false);
  const [notice, setNotice] = useState(
    Boolean((location.state as { justCreated?: boolean } | null)?.justCreated),
  );
  const [localSettled, setLocalSettled] = useState<FocusSession | null>(null);
  const [confirmEnd, setConfirmEnd] = useState(false);
  const [editingSession, setEditingSession] = useState<FocusSession | null>(
    null,
  );
  const [heartbeatFailed, setHeartbeatFailed] = useState(false);
  const [conflict, setConflict] = useState(false);
  const [offlineAction, setOfflineAction] = useState(false);
  const [showAllFriends, setShowAllFriends] = useState(false);
  const [editingGoal, setEditingGoal] = useState(false);
  const reconciledDeadline = useRef<string | undefined>(undefined);
  const heartbeatSession = query.data?.snapshot.my_session;
  const heartbeatSessionId =
    heartbeatSession?.status === 'focusing' ||
    heartbeatSession?.status === 'paused'
      ? heartbeatSession.session_id
      : undefined;
  const commandIntent = useIntentKey();
  const seenIntent = useIntentKey();
  const goalIntent = useIntentKey();
  const updateSession = (session: FocusSession) => {
    if (session.status === 'completed' || session.status === 'discarded')
      setLocalSettled(session);
    void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
  };
  const command = useMutation({
    mutationFn: ({
      name,
      params,
      key,
    }: {
      name: string;
      params: Record<string, unknown>;
      key: string;
    }) =>
      rpc<{ session: FocusSession }>(name, { ...params, idempotency_key: key }),
    onSuccess: ({ data }) => {
      commandIntent.clear();
      setConflict(false);
      setOfflineAction(false);
      updateSession(data.session);
    },
    onError: (error) => {
      if (error instanceof ApiError && isFocusSession(error.authoritativeState))
        updateSession(error.authoritativeState);
      if (
        error instanceof ApiError &&
        ['TRANSPORT_ERROR', 'REQUEST_TIMEOUT', 'NETWORK_UNCONFIRMED'].includes(
          error.code,
        )
      )
        setOfflineAction(true);
      if (error instanceof ApiError && focusConflictCodes.has(error.code)) {
        setConflict(true);
        void queryClient
          .refetchQueries({ queryKey: ['home', spaceId], exact: true })
          .finally(() => setConflict(false));
      } else
        void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
    },
  });
  const realtimeConnection = useRoomRealtime(
    spaceId,
    query.dataUpdatedAt,
    Boolean(query.error || command.error || heartbeatFailed),
  );
  const connection: ConnectionState = conflict
    ? 'conflict'
    : heartbeatFailed && realtimeConnection === 'connected'
      ? 'unconfirmed'
      : realtimeConnection;
  const markAchievement = useMutation({
    mutationFn: (achievementId: string) =>
      rpc('mark_achievement_seen', {
        achievement_id: achievementId,
        idempotency_key: seenIntent.get(achievementId),
      }),
    onSuccess: () => {
      seenIntent.clear();
      void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
      void queryClient.invalidateQueries({
        queryKey: ['achievements', spaceId],
      });
    },
    retry: 2,
  });
  const updateDailyGoal = useMutation({
    mutationFn: ({
      scope,
      targetMinutes,
    }: {
      scope: 'today' | 'future_default';
      targetMinutes: number;
    }) =>
      rpc<PersonalDailyGoalResult>('set_personal_daily_goal', {
        space_id: spaceId,
        scope,
        target_minutes: targetMinutes,
        idempotency_key: goalIntent.get(`${scope}:${targetMinutes}`),
      }),
    onSuccess: ({ data: result }) => {
      goalIntent.clear();
      queryClient.setQueryData<SnapshotResult>(
        ['home', spaceId],
        (current) =>
          current && {
            ...current,
            snapshot: applyPersonalDailyGoal(current.snapshot, result),
          },
      );
      setEditingGoal(false);
      void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
    },
  });
  const unseenAchievementId =
    query.data?.snapshot.unseen_achievement?.achievement_id;
  useAutoAcknowledge(unseenAchievementId, (achievementId) =>
    markAchievement.mutate(achievementId),
  );
  const unseenPersonalAchievement =
    query.data?.snapshot.unseen_personal_achievement;
  useAutoAcknowledge(
    unseenPersonalAchievement
      ? `personal:${unseenPersonalAchievement.achievement_id}`
      : undefined,
    () => {
      void rpc('mark_achievement_tab_seen', {
        space_id: spaceId,
        tab: 'personal',
      }).then(() => {
        void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
        void queryClient.invalidateQueries({
          queryKey: ['nav-notifications', spaceId],
        });
      });
    },
  );
  useEffect(() => {
    if (!heartbeatSessionId) return;
    let timer: number | undefined;
    const heartbeat = () => {
      if (document.visibilityState !== 'visible') return;
      void rpc<{ session: FocusSession }>('heartbeat_focus', {
        session_id: heartbeatSessionId,
      })
        .then(({ data }) => {
          setHeartbeatFailed(false);
          if (
            data.session.status === 'completed' ||
            data.session.status === 'discarded'
          )
            setLocalSettled(data.session);
          void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
        })
        .catch(() => setHeartbeatFailed(true));
    };
    const stop = () => {
      if (timer !== undefined) window.clearInterval(timer);
      timer = undefined;
    };
    const start = () => {
      stop();
      if (document.visibilityState !== 'visible') return;
      heartbeat();
      timer = window.setInterval(heartbeat, 45_000);
    };
    const onVisibilityChange = () => {
      if (document.visibilityState === 'visible') start();
      else stop();
    };
    document.addEventListener('visibilitychange', onVisibilityChange);
    start();
    return () => {
      stop();
      document.removeEventListener('visibilitychange', onVisibilityChange);
    };
  }, [heartbeatSessionId, queryClient, spaceId]);
  useEffect(() => {
    const session = query.data?.snapshot.my_session;
    if (
      !session ||
      (session.status !== 'focusing' && session.status !== 'paused') ||
      !session.auto_settle_at
    ) {
      reconciledDeadline.current = undefined;
      return;
    }
    const deadlineKey = `${session.session_id}:${session.auto_settle_at}`;
    if (
      now >= Date.parse(session.auto_settle_at) &&
      reconciledDeadline.current !== deadlineKey
    ) {
      reconciledDeadline.current = deadlineKey;
      void query.refetch();
    }
  }, [now, query, query.data?.snapshot.my_session]);
  if (query.isLoading)
    return (
      <div className="page">
        <PageLoader />
      </div>
    );
  if (!query.data)
    return (
      <div className="page">
        <ErrorState onRetry={() => void query.refetch()} />
      </div>
    );
  const data = query.data.snapshot;
  const session = localSettled ?? data.my_session;
  const timingAnnouncement = command.isPending
    ? '正在同步专注状态'
    : session?.status === 'focusing'
      ? '专注已开始'
      : session?.status === 'paused'
        ? '专注已暂停'
        : session?.status === 'completed' || session?.status === 'discarded'
          ? '专注已结束'
          : '当前未在专注';
  const runCommand = (name: string, params: Record<string, unknown>) => {
    if (connection === 'offline' || navigator.onLine === false) {
      setOfflineAction(true);
      return;
    }
    setOfflineAction(false);
    command.mutate({
      name,
      params,
      key: commandIntent.get(`${name}:${JSON.stringify(params)}`),
    });
  };
  const start = (task: string, category: FocusCategory) => {
    if (navigator.onLine === false) {
      setOfflineAction(true);
      setDrawer(false);
      return;
    }
    command.mutate(
      {
        name: 'start_focus',
        params: { space_id: spaceId, task_name: task, category },
        key: commandIntent.get(`start_focus:${spaceId}:${task}:${category}`),
      },
      { onSuccess: () => setDrawer(false) },
    );
  };
  const updateTask = (task: string, category: FocusCategory) => {
    if (!editingSession) return;
    if (connection === 'offline' || navigator.onLine === false) {
      setOfflineAction(true);
      return;
    }
    command.mutate(
      {
        name: 'update_focus_task',
        params: {
          session_id: editingSession.session_id,
          task_name: task,
          category,
        },
        key: commandIntent.get(
          `update_focus_task:${editingSession.session_id}:${task}:${category}`,
        ),
      },
      { onSuccess: () => setEditingSession(null) },
    );
  };
  const end = () => {
    if (!session) return;
    const seconds = calculateFocusSeconds(session, now);
    if (seconds < 300 && !confirmEnd) {
      setConfirmEnd(true);
      return;
    }
    setConfirmEnd(false);
    runCommand('end_focus', { session_id: session.session_id });
  };
  return (
    <div className="page home-page">
      <span className="sr-only" aria-live="polite" aria-atomic="true">
        {timingAnnouncement}
      </span>
      <header className="page-header">
        <div>
          <p className="eyebrow">{data.space.active_member_count} 人的友间</p>
          <h1>{data.space.name}</h1>
        </div>
      </header>
      {connectionCopy[connection] && (
        <div
          className={`connection-banner connection-banner--${connection}`}
          role="status"
        >
          <Icon name={connection === 'offline' ? 'warning' : 'wifi'} />
          {connectionCopy[connection]}
        </div>
      )}
      {query.error && (
        <div className="inline-notice inline-notice--warning" role="status">
          部分内容暂时没有更新。上次数据仍保留，计时状态正在重新确认。
          <button type="button" onClick={() => void query.refetch()}>
            重新加载
          </button>
        </div>
      )}
      {notice && (
        <div className="inline-notice inline-notice--success" role="status">
          <Icon name="check" />
          友间已创建。邀请链接已安全保存在这台设备的设置页。
          <button onClick={() => setNotice(false)} aria-label="关闭提示">
            ×
          </button>
        </div>
      )}
      <Summary data={data.today} onEdit={() => setEditingGoal(true)} />
      {session ? (
        <FocusPanel
          session={session}
          now={now}
          connection={connection}
          pending={command.isPending}
          onPause={() =>
            runCommand('pause_focus', { session_id: session.session_id })
          }
          onResume={() =>
            runCommand('resume_focus', { session_id: session.session_id })
          }
          onEnd={end}
          onEdit={() => setEditingSession(session)}
          onDismiss={() => {
            setLocalSettled(null);
            void queryClient.invalidateQueries({ queryKey: ['home', spaceId] });
          }}
        />
      ) : (
        <section className="focus-panel focus-panel--idle">
          <Lamp />
          <h2>留一段完整的时间给自己</h2>
          <p>准备好后，点亮台灯开始专注。</p>
          <button
            className="button button--primary button--wide"
            onClick={() => setDrawer(true)}
          >
            开始专注
          </button>
        </section>
      )}
      {editingGoal && (
        <DailyGoalDrawer
          today={data.today}
          pending={updateDailyGoal.isPending}
          error={
            updateDailyGoal.error instanceof Error
              ? updateDailyGoal.error.message
              : undefined
          }
          onClose={() => setEditingGoal(false)}
          onSave={(scope, targetMinutes) =>
            updateDailyGoal.mutate({ scope, targetMinutes })
          }
        />
      )}
      {editingSession && (
        <EditTaskDrawer
          session={editingSession}
          pending={command.isPending}
          onClose={() => setEditingSession(null)}
          onSave={updateTask}
        />
      )}
      {command.error && (
        <div className="inline-notice inline-notice--error" role="alert">
          {command.error instanceof ApiError
            ? command.error.message
            : '这次操作还没有生效，请稍后重试。'}
        </div>
      )}
      {offlineAction && (
        <div className="inline-notice inline-notice--warning" role="status">
          当前无法连接服务器，这次操作还没有生效，专注计时仍在继续。连接恢复后请重试。
        </div>
      )}
      <section className="section">
        <div className="section-heading">
          <h2>正在亮灯</h2>
          <span>{data.focusing_members.length} 人</span>
        </div>
        {data.focusing_members.length ? (
          <div className="member-list">
            {data.focusing_members
              .slice(0, showAllFriends ? undefined : 4)
              .map((member) => (
                <article className="member-card" key={member.member_id}>
                  <Lamp state="focusing" compact />
                  <div>
                    <h3>{member.display_name}</h3>
                    <p>{member.task_name}</p>
                    <TaskHistory history={member.task_history ?? []} />
                    <small>
                      {categoryLabels[member.category]} ·{' '}
                      {formatDuration(
                        member.accumulated_focus_seconds +
                          Math.max(
                            0,
                            Math.floor(
                              (now -
                                Date.parse(member.active_segment_started_at)) /
                                1000,
                            ),
                          ),
                      )}
                    </small>
                    {member.connection.status === 'unconfirmed' && (
                      <span className="member-card__uncertain">
                        连接状态不可确认 · 最后同步于{' '}
                        {
                          formatLocalDateTime(
                            member.connection.last_seen_at,
                          ).split(' ')[1]
                        }
                      </span>
                    )}
                  </div>
                  <span className="status-dot">
                    <span className="sr-only">正在专注</span>
                  </span>
                </article>
              ))}
            {data.focusing_members.length > 4 && (
              <button
                className="button button--text button--full"
                type="button"
                onClick={() => setShowAllFriends((value) => !value)}
              >
                {showAllFriends
                  ? '收起好友'
                  : `查看全部 ${data.focusing_members.length} 人`}
              </button>
            )}
          </div>
        ) : (
          <EmptyState title="现在还没有人亮灯">
            <p>
              {session?.status === 'focusing'
                ? '你的灯已经亮了。朋友加入后会在这里出现。'
                : '你可以先开始，朋友打开友间后就能看到。'}
            </p>
          </EmptyState>
        )}
      </section>
      {data.active_goal_summary ? (
        <Link className="goal-summary" to="goals">
          <div>
            <p className="eyebrow">当前共同目标</p>
            <h2>一起完成这一段</h2>
          </div>
          <strong>
            {data.active_goal_summary.progress.credited_value === null
              ? '共同进行中'
              : `${Math.min(100, Math.round((data.active_goal_summary.progress.credited_value / data.active_goal_summary.target_value) * 100))}%`}
          </strong>
        </Link>
      ) : (
        <Link className="goal-summary goal-summary--empty" to="goals">
          <div>
            <p className="eyebrow">共同目标</p>
            <h2>一起定个目标</h2>
          </div>
          <strong aria-hidden="true">→</strong>
        </Link>
      )}
      {data.unseen_achievement && (
        <section className="achievement-toast">
          <span>
            <Icon name="sparkle" />
          </span>
          <div>
            <small>获得共同成就</small>
            <strong>
              {achievementTitle(data.unseen_achievement.achievement_type)}
            </strong>
          </div>
          <small>已记录，可在统计页查看</small>
        </section>
      )}
      {data.unseen_personal_achievement && (
        <section className="achievement-toast">
          <span>
            <Icon name="sparkle" />
          </span>
          <div>
            <small>获得个人成就</small>
            <strong>
              {achievementTitle(
                data.unseen_personal_achievement.achievement_type,
              )}
            </strong>
          </div>
          <small>已记录，可在成就页查看</small>
        </section>
      )}
      {drawer && (
        <StartDrawer
          pending={command.isPending}
          onClose={() => setDrawer(false)}
          onStart={start}
        />
      )}
      {confirmEnd && (
        <AccessibleModal
          kind="dialog"
          titleId="end-title"
          onClose={() => setConfirmEnd(false)}
        >
          <h2 id="end-title">现在结束吗？</h2>
          <p>结束后这段记录会保留，但少于 5 分钟不会计入统计。</p>
          <div className="dialog__actions">
            <button
              data-autofocus
              className="button button--secondary"
              onClick={() => setConfirmEnd(false)}
            >
              继续专注
            </button>
            <button className="button button--danger" onClick={end}>
              确认结束
            </button>
          </div>
        </AccessibleModal>
      )}
    </div>
  );
}

function isFocusSession(value: unknown): value is FocusSession {
  return Boolean(
    value &&
    typeof value === 'object' &&
    'session_id' in value &&
    'status' in value,
  );
}

function achievementTitle(type: string) {
  return (
    (
      {
        together_lit: '同日亮灯',
        three_days_together: '三日相伴',
        first_goal: '第一个共同目标',
        focus_milestone: '时光里程碑',
        night_owl: '挑灯夜战',
        dawn_walker: '破晓而行',
        solo_focus: '孤军奋战',
        unbroken_focus: '一气呵成',
        double_focus: '梅开二度',
        triple_focus: '三顾书桌',
        three_categories: '六边形战士',
        promise_keeper: '守约者',
        return_after_break: '久别重逢',
      } as Record<string, string>
    )[type] ?? '共同的光'
  );
}
