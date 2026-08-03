# 友间（Youjian）MVP 技术设计

> 依赖：[UI_STATE_SPEC.md](./UI_STATE_SPEC.md)、[API_CONTRACT.md](./API_CONTRACT.md)
> 技术栈：React + TypeScript + Vite PWA + Supabase Auth/PostgreSQL/Realtime/Cron  
> 已冻结规则：每日打卡 60 分钟；一个匿名身份只加入一个友间。两项均通过配置和服务端规则实现，不写死在 UI。

## 1. 架构目标

总体原则是**服务端权威**：浏览器负责表达意图和显示结果，PostgreSQL 负责判定合法状态、时间与最终统计。

- 服务端时间是计时唯一权威；
- 客户端只能请求状态转换，不能提交累计分钟数；
- 同一用户最多有一条活动专注记录；
- 记录结算后不可编辑或删除；
- 暂停、恢复、手动结束和自动结算在并发下只生效一次；
- 房间成员只能读取本房间的数据；
- 邀请链接泄露时可以由房主立即轮换；
- 手机后台或断网不停止服务器端计时；
- 日、周、月统计可按个人时区和房间时区正确拆分；
- 数据结构不阻止未来支持多友间，但 MVP 服务端正式禁止第二个活动友间成员关系。

## 2. 系统边界

```text
React PWA
├── Supabase Anonymous Auth
├── PostgreSQL RPC（所有业务写入）
├── Supabase Realtime（房间状态变化）
└── 静态资源缓存（不缓存私密 API 响应）

PostgreSQL
├── RLS
├── 事务化状态机
├── 不可变事件日志
├── 专注区间与统计函数
└── pg_cron 每分钟自动结算／过期
```

不设置独立常驻后端。需要隐藏权限的操作由 `security definer` 数据库函数承担；只有确实需要第三方服务时才引入 Edge Function。MVP 不需要 Edge Function。

## 3. 前端工程结构

建议目录：

```text
src/
├── app/
│   ├── router.tsx
│   ├── providers.tsx
│   └── queryClient.ts
├── auth/
│   ├── anonymousAuth.ts
│   └── membershipGuard.tsx
├── features/
│   ├── onboarding/
│   ├── focus/
│   ├── space/
│   ├── stats/
│   ├── goals/
│   ├── achievements/
│   ├── settings/
│   └── pwa/
├── components/
│   ├── ui/
│   └── business/
├── lib/
│   ├── supabase.ts
│   ├── serverClock.ts
│   ├── connectionMonitor.ts
│   └── errors.ts
├── routes/
└── styles/
```

建议依赖：

- React Router：路由与成员守卫；
- TanStack Query：服务端状态、重试与缓存失效；
- Zod：表单和 RPC 返回值校验；
- `@supabase/supabase-js`：认证、RPC 与 Realtime；
- `vite-plugin-pwa`：manifest 和 Service Worker 构建。

不引入 Redux。当前领域状态可由 TanStack Query、局部 reducer 和专注状态机模块处理。

## 4. 路由

```text
/                         欢迎／回到友间
/create                   创建友间
/invite/:token            邀请预览与加入
/space/:spaceId           首页
/space/:spaceId/stats     统计
/space/:spaceId/goals     共同目标
/space/:spaceId/settings  设置
```

守卫顺序：

1. 确认匿名 Auth session；
2. 确认当前用户是否为目标友间的活动成员；
3. 读取角色；
4. 停用成员立即取消订阅并清理缓存；
5. 非成员只能访问邀请预览 RPC 返回的有限字段。

## 5. 数据模型

所有主键使用 UUID。所有时间字段使用 `timestamptz`。累计秒数使用非负整数，服务端展示时再格式化。

### 5.1 `profiles`

```text
id uuid PK -> auth.users.id
timezone text NOT NULL
created_at timestamptz NOT NULL DEFAULT now()
updated_at timestamptz NOT NULL DEFAULT now()
```

昵称不放在全局 `profiles` 中。昵称属于友间成员身份，未来多友间可以使用不同昵称。

约束：

- `timezone` 必须由服务端校验为可识别的 IANA 时区；
- 客户端只能更新自己的时区；
- MVP 中时区首次确定后仅允许通过受控 RPC 修改，历史统计始终按查询时的当前个人时区展示。

### 5.2 `spaces`

```text
id uuid PK
name text NOT NULL
owner_id uuid NOT NULL -> auth.users.id
timezone text NOT NULL
member_limit smallint NOT NULL DEFAULT 3
daily_checkin_target_minutes smallint NOT NULL DEFAULT 60
invite_token_hash text NOT NULL UNIQUE
invite_version integer NOT NULL DEFAULT 1
created_at timestamptz NOT NULL DEFAULT now()
```

约束：

- 名称去除首尾空格后 1～30 字；
- `member_limit BETWEEN 2 AND 12`；
- 名称可由房主通过幂等 RPC 修改；成员上限只允许提高，不允许降低；两者均不轮换邀请 token；
- `daily_checkin_target_minutes BETWEEN 5 AND 720`；
- 房间时区创建后不可修改；
- `owner_id` 必须存在对应活动成员且角色为 `owner`。

### 5.3 `space_members`

```text
id uuid PK
space_id uuid NOT NULL -> spaces.id
user_id uuid NOT NULL -> auth.users.id
display_name text NOT NULL
role member_role NOT NULL
status member_status NOT NULL DEFAULT 'active'
joined_at timestamptz NOT NULL DEFAULT now()
disabled_at timestamptz NULL
disabled_by uuid NULL -> auth.users.id
```

枚举：

```text
member_role   = owner | member
member_status = active | disabled
```

约束：

- `UNIQUE(space_id, user_id)`；
- 活动昵称在同一友间内大小写不敏感唯一；
- 昵称去除首尾空格后 1～20 字；
- 每个友间只能有一个 `owner`；
- 房主不能被停用；
- `disabled` 必须同时具有 `disabled_at` 和 `disabled_by`。

数据库保留多条不同 `space_id` 的成员关系。MVP 的 `join_space` 函数检查应用配置并拒绝加入第二个友间，不建立永久性的数据库唯一约束。

### 5.4 `focus_sessions`

```text
id uuid PK
space_id uuid NOT NULL -> spaces.id
user_id uuid NOT NULL -> auth.users.id
member_id uuid NOT NULL -> space_members.id
task_name text NOT NULL
category focus_category NULL
status focus_status NOT NULL
accumulated_focus_seconds integer NOT NULL DEFAULT 0
active_segment_started_at timestamptz NULL
paused_at timestamptz NULL
started_at timestamptz NOT NULL
completed_at timestamptz NULL
completion_reason completion_reason NULL
last_seen_at timestamptz NOT NULL
unconfirmed_connection_seconds integer NOT NULL DEFAULT 0
created_at timestamptz NOT NULL DEFAULT now()
```

枚举：

```text
focus_category    = study | work | reading | exercise | other
focus_status      = focusing | paused | completed | discarded
completion_reason = manual_end | pause_timeout | focus_limit | member_disabled
```

关键约束：

- 任务名称去除首尾空格后 1～80 字；
- `accumulated_focus_seconds >= 0`；
- `unconfirmed_connection_seconds >= 0`；
- `focusing` 必须有 `active_segment_started_at`，不得有 `paused_at`；
- `paused` 必须有 `paused_at`，不得有 `active_segment_started_at`；
- `completed/discarded` 必须有 `completed_at` 和 `completion_reason`；
- `completed/discarded` 不得保留活动或暂停时间戳；
- 对 `user_id` 建立部分唯一索引，只允许一条 `focusing/paused` 记录；
- 客户端不得直接 INSERT、UPDATE 或 DELETE。

`accumulated_focus_seconds` 保存已经关闭的专注区间总秒数。处于 `focusing` 时，实时值为：

```text
accumulated_focus_seconds
+ max(0, server_now - active_segment_started_at)
```

### 5.5 `focus_segments`

```text
id uuid PK
session_id uuid NOT NULL -> focus_sessions.id
started_at timestamptz NOT NULL
ended_at timestamptz NULL
created_at timestamptz NOT NULL DEFAULT now()
```

每次开始或恢复创建一个区间；暂停、结束或达到上限时关闭当前区间。

约束：

- 同一 session 只能有一个 `ended_at IS NULL` 的区间；
- `ended_at > started_at`；
- 已关闭区间不允许客户端修改或删除；
- 跨日统计只读取 `focus_segments`，天然排除暂停时间。

`focus_sessions.accumulated_focus_seconds` 是状态转换的快速汇总；`focus_segments` 是统计与审计的事实来源。结算时校验两者一致。

### 5.6 `focus_events`

```text
id bigint generated always as identity PK
session_id uuid NOT NULL -> focus_sessions.id
actor_id uuid NULL -> auth.users.id
event_type focus_event_type NOT NULL
occurred_at timestamptz NOT NULL DEFAULT now()
metadata jsonb NOT NULL DEFAULT '{}'
```

事件：

```text
started | paused | resumed | completed |
connection_unconfirmed | reconnected | task_updated
```

只允许服务端函数追加，禁止任何 UPDATE 和 DELETE。自动事件的 `actor_id` 可为空，原因写入 `metadata`。`task_updated` 的 metadata 保存修改前后的任务名和分类；首页快照据此生成按时间倒序的共享 `task_history`。

### 5.7 `focus_connection_intervals`

```text
id uuid PK
session_id uuid NOT NULL -> focus_sessions.id
started_at timestamptz NOT NULL
ended_at timestamptz NULL
detected_from_last_seen_at timestamptz NOT NULL
```

用途：保存近似的“连接状态不可确认”区间。

约束：

- 同一 session 最多一个未关闭区间；
- session 结束时自动关闭未确认区间；
- 统计只显示近似分钟，不把该表作为专注有效性判断依据。

### 5.8 共同目标

#### `goal_proposals`

```text
id uuid PK
space_id uuid NOT NULL
proposer_member_id uuid NOT NULL
goal_type goal_type NOT NULL
period_type period_type NOT NULL
target_value integer NOT NULL
status proposal_status NOT NULL
expires_at timestamptz NOT NULL
effective_period_start timestamptz NOT NULL
created_at timestamptz NOT NULL DEFAULT now()
resolved_at timestamptz NULL
```

枚举：

```text
goal_type       = group_total_minutes | per_member_minutes | shared_checkin_days
period_type     = daily | weekly | monthly
proposal_status = pending | accepted | rejected | expired
```

#### `goal_proposal_members`

保存提案创建时需要投票的成员快照：

```text
proposal_id uuid
member_id uuid
vote goal_vote NULL
voted_at timestamptz NULL
PRIMARY KEY(proposal_id, member_id)
```

`goal_vote = accepted | rejected`。

成员在提案 pending 时被停用：从必需投票集合中移除，再判断剩余成员是否已经全员接受。新加入成员不追加到已经创建的提案。

同一友间只能存在一个 pending 提案或 scheduled／active 目标。全员通过时，以通过时刻和友间时区计算范围：次日 00:00 开始；daily 持续 1 天、weekly 持续 7 天、monthly 持续至下月同日。提案阶段的预览日期仅供说明，最终日期在最后一票事务中重新计算。

#### `goals`

```text
id uuid PK
source_proposal_id uuid UNIQUE NOT NULL
space_id uuid NOT NULL
goal_type goal_type NOT NULL
period_type period_type NOT NULL
target_value integer NOT NULL
starts_at timestamptz NOT NULL
ends_at timestamptz NOT NULL
status goal_status NOT NULL
completed_at timestamptz NULL
created_at timestamptz NOT NULL DEFAULT now()
```

`goal_status = scheduled | active | completed | failed`。

#### `goal_participants`

目标通过时冻结参与成员：

```text
goal_id uuid
member_id uuid
PRIMARY KEY(goal_id, member_id)
```

生效后加入或停用成员不改变这一周期目标参与者，不推翻已完成结果。被停用成员不能继续贡献新时长，但其停用前产生的有效时长保留。

### 5.9 `achievements`

```text
id uuid PK
space_id uuid NOT NULL
achievement_type achievement_type NOT NULL
dedupe_key text NOT NULL
earned_at timestamptz NOT NULL
metadata jsonb NOT NULL DEFAULT '{}'
tier text NOT NULL DEFAULT 'bronze'
participants_recorded boolean NOT NULL DEFAULT false
UNIQUE(space_id, dedupe_key)
```

`dedupe_key` 保证同一业务事件不会重复授予。

`tier = bronze | silver | gold`。等级是服务端事实；前端使用对应的铜、银、金星星底色和边框，不显示等级文字。

#### `achievement_participants`

```text
achievement_id uuid
member_id uuid
display_name_snapshot text NOT NULL
participation_days integer NOT NULL DEFAULT 1
PRIMARY KEY(achievement_id, member_id)
```

姓名和参与天数在授予时冻结。目标成就从 `goal_participants` 复制；共同连续成就聚合对应日期的每日参与快照；旧数据只有在事实足够可靠时回填，并用 `participants_recorded` 区分。

#### `achievement_reads`

```text
achievement_id uuid
member_id uuid
seen_at timestamptz NOT NULL DEFAULT now()
PRIMARY KEY(achievement_id, member_id)
```

成就是友间共有事实，已读状态按成员分别保存。

### 5.10 幂等命令

`focus_commands`：

```text
actor_id uuid NOT NULL
idempotency_key uuid NOT NULL -- 客户端生成
command_type text NOT NULL
request_hash text NOT NULL
session_id uuid NULL
result jsonb NOT NULL
created_at timestamptz NOT NULL DEFAULT now()
PRIMARY KEY(actor_id, idempotency_key)
```

所有状态转换 RPC 接受 `p_idempotency_key`。相同用户重复提交相同键时先比较请求 hash；参数一致则返回原结果，不重复执行，参数不同则拒绝。

## 6. 服务端状态转换

### 6.1 `start_focus`

输入：

```text
space_id, task_name, category, idempotency_key
```

事务：

1. 锁定当前用户相关活动 session；
2. 验证是目标友间活动成员；
3. 执行到期记录惰性结算；
4. 若仍有活动记录，返回该记录并标记冲突；
5. 用 `now()` 创建 `focusing` session；
6. 创建首个 open segment；
7. 追加 `started` 事件；
8. 保存幂等结果并返回。

### 6.2 `update_focus_task`

前置：当前用户拥有目标 session，成员仍为 active，session 状态为 `focusing` 或 `paused`。

事务锁定 session 并先执行到期结算；若仍活动且内容有变化，则更新 `task_name/category/version` 并追加一条 `task_updated` 事件。无变化请求只保存幂等结果，不产生事件。该命令不修改 segment、累计秒数或统计归属。

### 6.3 `pause_focus`

前置：当前用户拥有目标 session 且状态为 `focusing`。

事务：

1. 锁定 session；
2. 计算当前 open segment 从开始到 `now()` 的秒数；
3. 若累计已达到 6 小时，改走 `focus_limit` 结算；
4. 关闭 segment；
5. 更新累计秒数；
6. 状态改为 `paused`，`paused_at=now()`；
7. 追加 `paused` 事件。

### 6.4 `resume_focus`

前置：状态为 `paused`。

事务：

1. 锁定 session；
2. 若 `now() >= paused_at + 15 minutes`，执行 `pause_timeout` 结算并返回已完成结果；
3. 状态改为 `focusing`；
4. 清空 `paused_at`；
5. 设置 `active_segment_started_at=now()`；
6. 创建新 open segment；
7. 追加 `resumed` 事件。

### 6.5 `end_focus`

状态为 `focusing`：先按 `now()` 关闭 open segment并累计。  
状态为 `paused`：结束点和有效专注终点均为 `paused_at`，不计入暂停时间。

随后：

1. 总实际专注 `< 300` 秒：状态设为 `discarded`；
2. 否则状态设为 `completed`；
3. `completion_reason=manual_end`；
4. 清空活动状态字段；
5. 关闭未确认连接区间；
6. 追加一次 `completed` 事件；
7. 触发打卡、目标和成就重算。

### 6.6 `settle_session`

内部函数，不向普通客户端直接开放。

处理优先级：

1. 已完成／丢弃：幂等返回；
2. `paused` 且暂停达到 15 分钟：按 `paused_at` 结算，原因 `pause_timeout`；
3. `focusing` 且总实际时长达到 6 小时：将 open segment 精确截断到第 6 小时，原因 `focus_limit`；
4. 其他情况不变。

六小时截断点：

```text
active_segment_started_at
+ (21600 - accumulated_focus_seconds) seconds
```

即使 Cron 晚运行数分钟，也只计算到这一准确时刻。

### 6.7 `disable_member`

仅房主可调用。

1. 验证目标不是房主；
2. 锁定成员及其活动 session；
3. 若正在专注，按 `now()` 结算；
4. 若暂停，按 `paused_at` 结算；
5. 结算原因 `member_disabled`；
6. 将成员设为 disabled；
7. 从 pending 提案的必需投票集合移除；
8. 重新判断提案是否全员接受；
9. 不修改历史目标和记录。

## 7. 邀请安全

### 7.1 Token

- 生成至少 256 bit 随机 token；
- URL 中使用 base64url 编码明文 token；
- 数据库只保存 SHA-256 hash；
- 日志不得记录完整邀请 URL；
- 房主重置时生成新 token、递增 `invite_version` 并覆盖 hash；
- 旧 token 立即无法通过预览和加入。

### 7.2 `get_invite_preview`

输入明文 token，只返回：

- space 名称；
- 房主昵称；
- 当前活动成员数；
- 人数上限；
- 房间时区；
- `valid/full` 状态。

不返回成员名单、任务、统计、目标或任何内部 ID。

### 7.3 `join_space`

输入：token、昵称、个人时区、幂等键。

事务内验证：

- token hash 匹配；
- 房间未满；
- 昵称未被活动成员占用；
- 当前匿名用户不是已停用成员；
- MVP 配置下没有另一个活动友间成员关系；
- 同一用户重复请求返回既有成员身份。

人数检查与 INSERT 必须在同一事务和锁中完成，避免两个人同时占用最后一个位置。

## 8. RLS 与数据库权限

### 8.1 原则

- 所有公开 schema 表启用 RLS；
- 浏览器只持有 publishable key；
- 客户端对核心业务表仅有必要 SELECT 权限；
- 所有写入通过受控 RPC；
- `service_role` 不进入前端、仓库或构建环境；
- `security definer` 函数固定 `search_path`，并显式检查 `auth.uid()`。

### 8.2 读取策略

| 表 | 允许读取者 |
|---|---|
| `profiles` | 本人；同房间成员只通过安全视图读取必要字段 |
| `spaces` | 活动成员 |
| `space_members` | 同一友间活动成员 |
| `focus_sessions` | 同一友间活动成员 |
| `focus_segments` | 同一友间活动成员，或只通过统计函数读取 |
| `focus_events` | session 所在友间活动成员 |
| 目标与成就 | 同一友间活动成员 |
| `focus_commands` | 仅本人对应记录，默认不开放 SELECT |

### 8.3 写入策略

普通客户端不得直接写入：

- `spaces`；
- `space_members`；
- `focus_sessions`；
- `focus_segments`；
- `focus_events`；
- 目标、投票与成就表。

只授予对应 RPC 的 `EXECUTE`。迁移后自动测试权限，确保直接 INSERT/UPDATE/DELETE 返回拒绝。

## 9. Realtime

### 9.1 订阅范围

进入友间后订阅：

- 本友间 `focus_sessions` 的 INSERT/UPDATE；
- 本友间 `space_members` 的 UPDATE；
- 本友间 `goal_proposals/goals` 的变化；
- 本友间 `achievements` 的 INSERT。

所有订阅以 `space_id` 过滤，并由 RLS 再次验证。

### 9.2 不依赖 Realtime 完成业务

Realtime 只用于加快刷新。以下时机必须主动查询服务端：

- 页面首次进入；
- 页面从后台回到前台；
- Realtime 重连成功；
- 暂停倒计时到 0；
- 任一状态转换返回；
- 本地与推送状态冲突。

### 9.3 显示时钟

每次查询响应带 `server_now`。前端计算：

```text
clock_offset = server_now - midpoint(request_sent_at, response_received_at)
```

界面使用 `Date.now() + clock_offset` 推算。网络延迟较高时只影响显示平滑度，不影响结算结果。

## 10. 心跳与连接状态不可确认

### 10.1 参数

- 页面前台且在线时，每 45 秒发送一次心跳；
- 连续 120 秒无心跳，服务端认为连接状态不可确认；
- 页面重新可见时立即发送心跳并同步 session；
- 心跳只更新 `last_seen_at`，不能改变专注状态。

### 10.2 区间记录

Cron 或读取函数发现：

```text
status = focusing
AND now() > last_seen_at + 120 seconds
```

则创建从 `last_seen_at + 120 seconds` 开始的未确认区间。重新心跳时关闭区间。

若 session 在未确认期间结算，以 `completed_at` 关闭区间。最终秒数向下取整到分钟展示，并附“约”字。

暂停状态不对好友展示，不需要生成面向好友的连接提示；但暂停用户自己的恢复同步仍遵循相同服务器核对原则。

## 11. Cron

每分钟执行一个数据库函数 `run_minute_maintenance()`：

1. 结算暂停满 15 分钟的 session；
2. 结算实际专注满 6 小时的 session；
3. 标记／关闭连接状态不可确认区间；
4. 将超过 48 小时的 pending 提案设为 expired；
5. 激活到期 scheduled 目标；
6. 完成本周期结束的 active 目标；
7. 触发相应成就去重写入。

函数分批处理并设置最大单批数量，避免异常数据导致任务运行超过一分钟。所有动作幂等，可安全重跑。

不自动清理匿名 Auth 用户，因为删除 Auth 用户会破坏历史记录外键和身份审计。

## 12. 跨日与统计

### 12.1 事实来源

统计只使用已关闭的 `focus_segments`，并要求所属 session 最终状态为 `completed`。`discarded` 的所有 segment 都排除。

正在进行的 session：

- 首页今日累计可以临时包含当前 open segment；
- 正式历史和完成打卡只在 session 结算后更新；
- 避免一段最终不足 5 分钟的进行中记录提前触发打卡。

### 12.2 跨日拆分

给定统计时区，把查询周期的本地日边界转换为 UTC 时间范围，然后计算 segment 与每个 UTC 范围的交集秒数。

```text
credited_seconds = duration(
  intersection(segment_range, local_day_as_utc_range)
)
```

夏令时地区必须由 PostgreSQL 时区数据库转换，不能假设每天固定 24 小时。

### 12.3 个人统计

- 以 `profiles.timezone` 划分日／周／月；
- 周一为一周开始；
- 当前连续打卡从个人本地“今天”向前计算；
- 每日达标值读取所属 `spaces.daily_checkin_target_minutes`；
- MVP 一人一友间，因此不存在跨友间累计。

### 12.4 友间统计

- 以 `spaces.timezone` 划分周期；
- 小组合计只计算本友间 session；
- 共同出勤按目标参与成员快照判断；
- 停用成员的历史数据仍保留在历史周期统计中。

### 12.5 缓存策略

MVP 数据量小，优先使用 SQL 函数实时聚合。为以下字段建立索引：

- `focus_sessions(space_id, user_id, status, started_at)`；
- `focus_segments(session_id, started_at, ended_at)`；
- `space_members(space_id, status)`；
- `goals(space_id, status, starts_at, ends_at)`。

在真实性能数据表明需要前，不引入每日聚合表或物化视图。

## 13. 共同目标计算

### 13.1 生效日期

- 全部周期从提案全员通过后的下一个本地自然日 00:00 开始；
- daily：结束于开始后的下一个本地自然日 00:00；
- weekly：结束于开始后的第 7 个本地自然日 00:00；
- monthly：结束于下月同一本地日期 00:00。

统一转换为 UTC `timestamptz` 保存。

提案创建时的 `effective_period_start` 仅用于预览；最终一票通过时在事务锁内重新计算并写回。已有 `scheduled` 或 `active` 目标、或已有 `pending` 提案时拒绝新提案，避免滚动周期重叠。

### 13.2 达成规则

#### 小组合计

参与成员在周期内有效 segment 交集秒数总和达到目标。

#### 每人门槛

每个 `goal_participants` 的有效秒数分别达到目标。所有人均达到才完成。

#### 共同出勤

按房间时区逐日判断：当日每个参与成员均达到房间每日打卡门槛，则共同完成天数加一。

目标可以提前完成；达到条件后记录第一次满足条件的服务器时间。周期结束仍未达到则标记 `failed`。

## 14. 成就计算

成就只从已结算有效 session、已完成目标和房间时区事实派生。

当前 `dedupe_key`：

```text
together-lit:{local_date}
together-streak:{1|3|7}
goal-count:{1|3|10}
milestone:{threshold_minutes}
```

共同连续 1／3／7 天分别为铜／银／金；完成共同目标 1／3／10 个分别为铜／银／金；累计专注 600／3000／6000 分钟分别为铜／银／金。成就规则配置在服务端，不由客户端上报。

迁移 `0034` 只修复仍处于 `scheduled` 的旧日历边界目标，将其按提案 `resolved_at` 重算为次日开始；active、completed、failed 的历史统计窗口保持不变。

## 15. PWA 与缓存

### 15.1 缓存范围

可以缓存：

- HTML 应用外壳；
- JS/CSS 构建产物；
- 字体、图标和品牌静态图片；
- 离线说明页。

禁止缓存：

- Supabase REST/RPC 响应；
- Realtime 消息；
- 邀请预览结果；
- 成员任务、统计和目标数据；
- Auth token 的自定义副本。

### 15.2 导航策略

- 导航请求：network-first，失败时回退缓存的应用外壳；
- 构建产物：按内容 hash cache-first；
- API：network-only；
- 新 Service Worker 安装后提示用户刷新，不在计时中强制 reload。

### 15.3 匿名 Auth

只使用 Supabase SDK 的安全会话存储。首次创建／加入后不提供显眼的“退出”按钮。检测到 session 缺失时不尝试按昵称恢复。

## 16. 错误模型

RPC 返回稳定业务错误码，前端映射为用户文案：

```text
INVITE_INVALID
SPACE_FULL
DISPLAY_NAME_TAKEN
ALREADY_IN_ANOTHER_SPACE
MEMBER_DISABLED
SESSION_ALREADY_ACTIVE
SESSION_NOT_ACTIVE
SESSION_ALREADY_SETTLED
PAUSE_TIMEOUT_SETTLED
FOCUS_LIMIT_SETTLED
NOT_SPACE_OWNER
NETWORK_UNCONFIRMED
```

响应同时返回：

- `code`：程序判断；
- `message`：开发日志；
- `server_now`：时间校准；
- `authoritative_state`：发生冲突时的最新状态；
- `request_id`：排查标识。

前端不直接展示数据库异常文本。

## 17. 隐私与日志

- 任务名称属于房间成员可见的私密内容；
- 日志默认不记录任务名称、昵称、邀请 token 和 Auth token；
- 错误日志记录内部 ID、请求 ID、错误码和状态转换，不记录完整正文；
- 前端监控不得采集输入框内容；
- 邀请预览接口做速率限制；
- Anonymous Auth 开启 CAPTCHA／Turnstile，防止批量创建垃圾用户；
- 所有环境使用独立 Supabase 项目或独立安全配置，不共用生产密钥。

## 18. 可观测性

至少记录：

- RPC 成功率与错误码分布；
- 状态转换冲突次数；
- Cron 每次处理数量、耗时和失败；
- Realtime 重连频率；
- 未确认连接区间数量和时长分布；
- 自动结算原因分布；
- 邀请预览与加入失败率。

业务指标必须使用去标识化聚合，不记录成员任务正文。

## 19. 测试策略

### 19.1 数据库单元测试

必须覆盖：

- 一个用户无法并行创建两个 session；
- 暂停精确关闭当前 segment；
- 恢复创建新 segment；
- 暂停第 14:59 可恢复，第 15:00 自动结算；
- 六小时只计算实际专注，不含暂停；
- Cron 延迟仍精确截断到六小时；
- 4:59 为 discarded，5:00 为 completed；
- 手动结束与 Cron 并发只产生一次完成事件；
- 跨午夜正确拆分；
- 夏令时切换日正确拆分；
- 邀请人数并发不超过上限；
- 重复幂等键不重复执行；
- 停用成员正确结算活动记录；
- pending 提案成员变化后正确重算；
- active 目标参与者快照不变化。

### 19.2 RLS 测试

- 非成员不能读取房间；
- A 房间成员不能读取 B 房间；
- 成员不能直接写计时表；
- 成员不能操作他人的 session；
- 普通成员不能停用成员或重置邀请；
- 停用后立即失去读取权限；
- 邀请预览只返回白名单字段。

### 19.3 前端状态测试

- 所有过渡状态禁用重复操作；
- 离线点击暂停／结束不显示成功；
- 后台恢复先核对服务端；
- 自动结算后显示正确原因；
- Realtime 事件重复或乱序不倒退状态；
- 320px、390px、768px 和桌面宽度布局正常；
- 键盘和屏幕阅读器可完成核心流程。

### 19.4 端到端场景

1. 设备 A 创建友间并邀请设备 B；
2. A、B 分别开始不同任务；
3. A 暂停，B 继续并实时看到 A 从列表移除；
4. A 恢复，再次出现；
5. A 锁屏，B 看到连接状态不可确认；
6. A 返回并同步；
7. B 主动结束并形成有效记录；
8. A 暂停超过 15 分钟后自动结算；
9. 跨午夜记录正确拆分；
10. 两人完成打卡并触发共同成就；
11. 提出、全员接受并在下一周期激活目标；
12. 房主轮换邀请并验证旧链接失效。

## 20. 迁移与实施顺序

1. 初始化 Vite/React/TypeScript/PWA；
2. 创建枚举、基础表和索引；
3. 建立 RLS 与权限测试；
4. 实现创建／邀请／加入 RPC；
5. 实现计时状态机、segments 和事件；
6. 实现 Cron 和惰性结算；
7. 实现首页与 Realtime；
8. 实现连接心跳；
9. 实现跨日统计和连续打卡；
10. 实现共同目标与成就；
11. 实现设置、成员停用和邀请轮换；
12. 完成 PWA、无障碍与端到端测试。

每一步先通过数据库不变量和权限测试，再接入页面。

## 21. 已冻结规则的技术实现

### 每日打卡门槛

存储于 `spaces.daily_checkin_target_minutes`，MVP 值为 60。前端从服务端响应读取，不维护另一份常量。

### 单身份友间数量

实现为服务端配置：

```text
allow_multiple_spaces = false
```

`join_space` 在 false 时返回 `ALREADY_IN_ANOTHER_SPACE`。数据库成员关系保留多友间能力，不增加全局唯一约束。

若首版改为 true，还必须先敲定：一条专注属于一个指定友间，还是同时向多个友间广播。当前技术设计采用“每条专注只属于一个友间”。

## 22. 技术完成标准

技术设计进入实现时，必须满足：

- [ ] 所有业务写操作都有服务端 RPC；
- [ ] 所有状态转换定义前置条件、事务和幂等行为；
- [ ] 跨日统计基于 focus segments；
- [ ] RLS 不依赖前端隐藏按钮；
- [ ] 邀请 token 只保存 hash；
- [ ] Cron 延迟不改变最终计时时长；
- [ ] 未确认连接不会影响专注有效性；
- [ ] 私密 API 不进入 Service Worker 缓存；
- [ ] 两项已冻结决策均通过配置和服务端规则表达；
- [ ] 测试覆盖时间边界、并发、权限和多设备标签页冲突。
