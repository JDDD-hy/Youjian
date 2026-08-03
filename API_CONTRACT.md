# 友间（Youjian）MVP RPC / API 契约

> 依赖：[UI_STATE_SPEC.md](./UI_STATE_SPEC.md)、[TECHNICAL_DESIGN.md](./TECHNICAL_DESIGN.md)
> 目的：固定前端与 Supabase PostgreSQL 函数之间的输入、输出、幂等、权限和错误语义。  
> 约定：示例使用 JSON 表达，实际由 Supabase `rpc()` 调用 PostgreSQL 函数。

## 1. 全局约定

### 1.1 命名与格式

- JSON 字段使用 `snake_case`；
- ID 使用 UUID 字符串；
- 时间使用 UTC ISO 8601，例如 `2026-07-27T06:42:00.000Z`；
- 时区使用 IANA 名称，例如 `Asia/Shanghai`；
- 时长传输统一使用整数秒或整数分钟，字段名必须包含单位；
- 枚举值使用小写英文；
- 用户可见文字由前端根据错误码本地化，服务端不返回可直接展示的技术异常。

### 1.2 响应信封

所有业务 RPC 返回：

```json
{
  "ok": true,
  "request_id": "7a0263af-4210-4af8-b07a-6bf31296c421",
  "server_now": "2026-07-27T06:42:00.000Z",
  "data": {}
}
```

业务失败：

```json
{
  "ok": false,
  "request_id": "7a0263af-4210-4af8-b07a-6bf31296c421",
  "server_now": "2026-07-27T06:42:00.000Z",
  "error": {
    "code": "DISPLAY_NAME_TAKEN",
    "details": {}
  },
  "authoritative_state": null
}
```

规则：

- `request_id` 每次服务端执行唯一；
- `server_now` 每次都返回，用于校准显示时钟；
- 状态冲突必须返回 `authoritative_state`；
- 未预期数据库错误统一映射为 `INTERNAL_ERROR`，真实异常只进入安全日志；
- HTTP／网络层失败与业务错误分开处理。

### 1.3 幂等键

所有写 RPC 接受：

```json
{
  "idempotency_key": "由客户端为本次用户意图生成的UUID"
}
```

规则：

- 用户点击一次生成一个键；
- 网络重试复用同一个键；
- 用户完成后发起新的操作必须生成新键；
- 同一用户、同一键在所有写 RPC 中代表唯一一次用户意图；参数一致时返回第一次成功结果；
- 同一键携带不同参数时返回 `IDEMPOTENCY_KEY_REUSED`；
- 幂等记录至少保留 30 天。

### 1.4 分页

历史列表使用游标分页：

```json
{
  "limit": 30,
  "cursor": "opaque-or-null"
}
```

- `limit` 默认 30，最大 100；
- 游标不可由客户端解释；
- 返回 `next_cursor`，没有下一页时为 `null`；
- 统计聚合不分页。

## 2. 认证生命周期

### 2.1 邀请预览

邀请预览不创建匿名 Auth 用户。页面先以 Supabase 公共 `anon` 角色调用 `get_invite_preview`。

只有用户提交“加入友间”时才调用：

```ts
supabase.auth.signInAnonymously()
```

避免每个打开邀请链接的访客都在 `auth.users` 中产生匿名身份。

### 2.2 创建友间

点击创建时先完成匿名登录，再调用 `create_space`。如果 RPC 失败，保留匿名 Auth session，允许用户重试，不重复创建身份。

### 2.3 会话恢复

应用启动：

1. 读取 Supabase Auth session；
2. 无 session：展示欢迎页；
3. 有 session：调用 `get_my_membership`；
4. 有活动成员关系：进入友间；
5. 没有活动关系：展示创建／邀请入口；
6. 只有 disabled 关系：不自动进入，展示停用说明。

## 3. 公共读取 RPC

### 3.1 `get_invite_preview`

权限：无需登录。  
速率限制：按 IP 和 token hash 限制。

输入：

```json
{
  "invite_token": "URL中的明文token"
}
```

成功：

```json
{
  "ok": true,
  "request_id": "...",
  "server_now": "2026-07-27T06:42:00.000Z",
  "data": {
    "status": "valid",
    "space_name": "我们的友间",
    "owner_display_name": "陈宇",
    "active_member_count": 2,
    "member_limit": 3,
    "space_timezone": "Asia/Shanghai"
  }
}
```

`status`：

```text
valid | full
```

失效 token 返回业务错误：

```json
{
  "code": "INVITE_INVALID",
  "details": {}
}
```

不得返回 `space_id`、成员列表、任务、目标或历史统计。

## 4. 身份与友间 RPC

### 4.1 `get_my_membership`

权限：已匿名登录。

输入：无。

成功，有活动成员关系：

```json
{
  "ok": true,
  "request_id": "...",
  "server_now": "...",
  "data": {
    "membership": {
      "member_id": "...",
      "space_id": "...",
      "display_name": "陈宇",
      "role": "owner",
      "status": "active",
      "joined_at": "..."
    },
    "latest_disabled_membership": null
  }
}
```

没有活动关系：`membership: null`。若当前身份曾被停用，`latest_disabled_membership` 返回最近一条被停用的友间名称、成员昵称和停用时间，供启动页显示明确结果；否则为 `null`。MVP 默认只返回一个活动关系，数据库未来允许扩展为数组。

### 4.2 `create_space`

权限：已匿名登录。

输入：

```json
{
  "display_name": "陈宇",
  "space_name": "我们的友间",
  "space_timezone": "Asia/Shanghai",
  "profile_timezone": "Asia/Shanghai",
  "member_limit": 3,
  "idempotency_key": "..."
}
```

成功：

```json
{
  "data": {
    "space": {
      "id": "...",
      "name": "我们的友间",
      "timezone": "Asia/Shanghai",
      "member_limit": 3,
      "daily_checkin_target_minutes": 60
    },
    "membership": {
      "member_id": "...",
      "display_name": "陈宇",
      "role": "owner",
      "status": "active"
    },
    "invite": {
      "invite_url": "https://example.com/invite/明文token"
    }
  }
}
```

明文邀请 token 只在创建和轮换成功响应中返回，数据库不保存明文。

错误：

- `ALREADY_IN_ANOTHER_SPACE`；
- `INVALID_DISPLAY_NAME`；
- `INVALID_SPACE_NAME`；
- `INVALID_TIMEZONE`；
- `INVALID_MEMBER_LIMIT`。

### 4.3 `join_space`

权限：已匿名登录。

输入：

```json
{
  "invite_token": "...",
  "display_name": "赵琳",
  "profile_timezone": "Asia/Shanghai",
  "idempotency_key": "..."
}
```

成功：

```json
{
  "data": {
    "space": {
      "id": "...",
      "name": "我们的友间",
      "timezone": "Asia/Shanghai",
      "member_limit": 3,
      "daily_checkin_target_minutes": 60
    },
    "membership": {
      "member_id": "...",
      "display_name": "赵琳",
      "role": "member",
      "status": "active"
    }
  }
}
```

错误：

- `INVITE_INVALID`；
- `SPACE_FULL`；
- `DISPLAY_NAME_TAKEN`；
- `ALREADY_IN_SPACE`，同时返回已有 membership；
- `ALREADY_IN_ANOTHER_SPACE`；
- `MEMBER_DISABLED`；
- `INVALID_TIMEZONE`。

## 5. 首页快照

### 5.1 `get_home_snapshot`

权限：目标友间活动成员。

输入：

```json
{
  "space_id": "..."
}
```

调用时先惰性结算当前到期 session 和目标状态。

成功：

```json
{
  "data": {
    "space": {
      "id": "...",
      "name": "我们的友间",
      "timezone": "Asia/Shanghai",
      "active_member_count": 2,
      "member_limit": 3,
      "daily_checkin_target_minutes": 60
    },
    "me": {
      "member_id": "...",
      "display_name": "陈宇",
      "role": "owner",
      "profile_timezone": "Asia/Shanghai"
    },
    "my_session": null,
    "focusing_members": [
      {
        "member_id": "...",
        "display_name": "赵琳",
        "session_id": "...",
        "task_name": "体育法阅读",
        "category": "reading",
        "status": "focusing",
        "accumulated_focus_seconds": 1200,
        "active_segment_started_at": "2026-07-27T06:22:00.000Z",
        "connection": {
          "status": "connected",
          "last_seen_at": "2026-07-27T06:41:45.000Z"
        }
      }
    ],
    "today": {
      "credited_focus_seconds": 2280,
      "checkin_target_seconds": 3600,
      "checkin_completed": false,
      "current_streak_days": 6
    },
    "active_goal_summary": null,
    "unseen_achievement": null
  }
}
```

`my_session` 使用第 6 节定义的权威 session 结构。`focusing_members` 不包含自己，也不包含 paused 成员。

连接状态：

```text
connected | unconfirmed
```

前端的 `offline/reconnecting/realtime_degraded` 是本地传输状态，不由该字段表达。

## 6. 权威 Session 结构

所有计时 RPC 返回相同结构：

```json
{
  "session_id": "...",
  "space_id": "...",
  "member_id": "...",
  "task_name": "体育法阅读",
  "category": "reading",
  "task_history": [
    {
      "task_name": "整理课程笔记",
      "category": "study",
      "changed_at": "2026-07-27T06:30:00.000Z"
    }
  ],
  "status": "focusing",
  "started_at": "2026-07-27T06:00:00.000Z",
  "accumulated_focus_seconds": 1800,
  "active_segment_started_at": "2026-07-27T06:35:00.000Z",
  "paused_at": null,
  "auto_settle_at": "2026-07-27T11:35:00.000Z",
  "completed_at": null,
  "completion_reason": null,
  "credited_focus_seconds": null,
  "counts_toward_stats": null,
  "connection": {
    "status": "connected",
    "last_seen_at": "2026-07-27T06:41:45.000Z",
    "unconfirmed_connection_seconds": 0
  }
}
```

字段规则：

- `auto_settle_at`：focusing 时为预计达到六小时的时间，paused 时为暂停满十五分钟时间；
- `credited_focus_seconds`：只有 completed/discarded 时返回最终值；
- `counts_toward_stats`：只有结算后为 true/false；
- focusing 的当前显示时长由累计值、活动段起点和 `server_now` 推算；
- completed/discarded 不返回活动段或暂停时间戳。
- `task_history` 按 `changed_at` 倒序返回修改前版本；当前任务没有修改时为空数组。该字段对同一友间的活动成员可见。

## 7. 专注命令 RPC

### 7.1 `start_focus`

输入：

```json
{
  "space_id": "...",
  "task_name": "体育法阅读",
  "category": "reading",
  "idempotency_key": "..."
}
```

成功：

```json
{
  "data": {
    "session": { "status": "focusing" }
  }
}
```

错误：

- `MEMBER_DISABLED`；
- `INVALID_TASK_NAME`；
- `INVALID_CATEGORY`；
- `SESSION_ALREADY_ACTIVE`，返回当前权威 session；
- `SPACE_ACCESS_DENIED`。

### 7.2 `update_focus_task`

输入：

```json
{
  "session_id": "...",
  "task_name": "完成体育法第二章",
  "category": "reading",
  "idempotency_key": "..."
}
```

仅 session 本人可在 `focusing` 或 `paused` 状态修改。成功返回更新后的权威 session；任务名和分类均未变化时成功返回且不追加历史。修改不重置计时、不创建新 session、不改变统计。已结算时返回 `SESSION_NOT_ACTIVE` 及权威 session。

### 7.3 `pause_focus`

输入：

```json
{
  "session_id": "...",
  "idempotency_key": "..."
}
```

成功返回 `status=paused`，其中 `auto_settle_at=paused_at+15min`。

可能返回已经结算的 session：当请求到达前实际专注已达到六小时，返回 `status=completed`、`completion_reason=focus_limit`，仍视为 `ok=true`，因为服务端成功解决了用户意图对应的状态。

错误：

- `SESSION_NOT_FOUND`；
- `SESSION_NOT_FOUND`（不存在和非本人统一返回，避免枚举其他成员 session）；
- `SESSION_NOT_FOCUSING`，返回权威状态；
- `MEMBER_DISABLED`。

### 7.4 `resume_focus`

输入：

```json
{
  "session_id": "...",
  "idempotency_key": "..."
}
```

成功可能为：

- `status=focusing`：恢复成功；
- `status=completed/discarded` 且 `completion_reason=pause_timeout`：已超时，不能恢复。

暂停已超时属于权威业务结果，返回 `ok=true`，让前端直接展示自动结算结果。

错误：

- `SESSION_NOT_FOUND`；
- `SESSION_NOT_FOUND`（不存在和非本人统一返回，避免枚举其他成员 session）；
- `SESSION_NOT_PAUSED`，返回权威状态；
- `MEMBER_DISABLED`。

### 7.5 `end_focus`

输入：

```json
{
  "session_id": "...",
  "idempotency_key": "..."
}
```

成功返回 `completed` 或 `discarded` session。

如果 Cron 已先完成结算，RPC 幂等地返回现有最终状态，不覆盖 `completion_reason`。

错误：

- `SESSION_NOT_FOUND`；
- `SESSION_NOT_FOUND`（不存在和非本人统一返回，避免枚举其他成员 session）；
- `MEMBER_DISABLED`，但若停用事务已完成 session，则返回最终权威状态。

### 7.6 `heartbeat_focus`

输入：

```json
{
  "session_id": "..."
}
```

成功：

```json
{
  "data": {
    "session": { "status": "focusing" },
    "connection_reconfirmed": true
  }
}
```

规则：

- 只接受 session 所有者；
- focusing 时更新 `last_seen_at`；
- paused 时只返回权威状态，不制造好友可见 presence；
- completed/discarded 时返回最终状态；
- 不要求幂等键，因为心跳本身是幂等覆盖；
- 客户端前台每 45 秒调用一次，失败不自动高频重试。

## 8. 专注事件 Realtime Payload

数据库变化通知仅作为失效提示，前端不直接信任其计算业务状态。

推荐最小 payload：

```json
{
  "space_id": "...",
  "entity": "focus_session",
  "entity_id": "...",
  "version": 7,
  "changed_at": "..."
}
```

收到后：

1. 比较 `version`；
2. 新版本才使首页 query 失效；
3. 重新调用 `get_home_snapshot`；
4. 不使用旧消息覆盖新快照。

每个会变化的实体包含递增 `version` 字段，解决 Realtime 重复或乱序问题。

## 9. 统计 RPC

### 9.1 `get_stats_summary`

输入：

```json
{
  "space_id": "...",
  "view": "mine",
  "period": "weekly",
  "anchor_local_date": "2026-07-27"
}
```

枚举：

```text
view   = mine | space
period = daily | weekly | monthly
```

成功：

```json
{
  "data": {
    "view": "mine",
    "period": "weekly",
    "timezone": "Asia/Shanghai",
    "period_start": "2026-07-21T00:00:00+08:00",
    "period_end": "2026-07-28T00:00:00+08:00",
    "credited_focus_seconds": 30240,
    "valid_session_count": 12,
    "checkin_day_count": 5,
    "days": [
      {
        "local_date": "2026-07-21",
        "credited_focus_seconds": 4200,
        "checkin_completed": true
      }
    ]
  }
}
```

`anchor_local_date` 按所选视角的时区解释。服务端校验日期格式和允许查询范围。

### 9.2 `list_focus_history`

输入：

```json
{
  "space_id": "...",
  "view": "mine",
  "period_start": "2026-07-20T16:00:00.000Z",
  "period_end": "2026-07-27T16:00:00.000Z",
  "limit": 30,
  "cursor": null
}
```

成功：

```json
{
  "data": {
    "items": [
      {
        "session_id": "...",
        "member": {
          "member_id": "...",
          "display_name": "赵琳"
        },
        "task_name": "体育法阅读",
        "category": "reading",
        "started_at": "...",
        "completed_at": "...",
        "credited_focus_seconds": 2520,
        "status": "completed",
        "completion_reason": "manual_end",
        "counts_toward_stats": true,
        "unconfirmed_connection_seconds": 180
      }
    ],
    "next_cursor": null
  }
}
```

### 9.3 `get_focus_session_detail`

输入：`session_id`。

返回 session、实际专注 segments、连接状态不可确认区间和结算说明。不默认返回原始事件 metadata，避免把内部审计结构绑定到 UI。

## 10. 共同目标 RPC

### 10.1 `get_goals_snapshot`

输入：`space_id`。

返回：

```json
{
  "data": {
    "active_goals": [],
    "scheduled_goals": [],
    "pending_proposals": [],
    "history": []
  }
}
```

提案结构：

```json
{
  "proposal_id": "...",
  "proposer": {
    "member_id": "...",
    "display_name": "赵琳"
  },
  "goal_type": "per_member_minutes",
  "period_type": "weekly",
  "target_value": 300,
  "status": "pending",
  "created_at": "...",
  "expires_at": "...",
  "effective_period_start": "...",
  "required_vote_count": 3,
  "accepted_vote_count": 1,
  "my_vote": null
}
```

目标结构：

```json
{
  "goal_id": "...",
  "goal_type": "group_total_minutes",
  "period_type": "weekly",
  "target_value": 1200,
  "status": "active",
  "starts_at": "...",
  "ends_at": "...",
  "progress": {
    "credited_value": 720,
    "completed": false,
    "members": null
  }
}
```

`per_member_minutes` 的 `members` 返回每个参与成员的当前值和是否达标；界面不得据此排序成排行榜。

### 10.2 `propose_goal`

输入：

```json
{
  "space_id": "...",
  "goal_type": "group_total_minutes",
  "period_type": "weekly",
  "target_value": 1200,
  "idempotency_key": "..."
}
```

规则：

- 分钟类目标的值使用整数分钟；
- 共同出勤使用整数天；
- 服务端计算过期时间和下一完整周期；
- 全员通过后，从友间时区的次日 00:00 开始；每日持续 1 天、每周持续 7 天、每月持续至下月同日；
- 发起人自动投接受票；
- 只有一个活动成员时拒绝创建共同目标；
- 同一友间同时只能存在一个 pending 提案或 scheduled／active 目标；
- 提交后不可修改。

错误：

- `INVALID_GOAL_TYPE`；
- `INVALID_PERIOD_TYPE`；
- `INVALID_TARGET_VALUE`；
- `NOT_ENOUGH_MEMBERS`；
- `GOAL_ALREADY_OPEN`；
- `MEMBER_DISABLED`。

### 10.3 `vote_goal_proposal`

输入：

```json
{
  "proposal_id": "...",
  "vote": "accepted",
  "idempotency_key": "..."
}
```

规则：

- 只能投一次最终票；
- 重复相同幂等请求返回原结果；
- 试图用新请求改票返回 `VOTE_ALREADY_FINAL`；
- 任一拒绝立即将提案设为 rejected；
- 最后一名成员接受时，在同一事务创建 scheduled goal 和参与者快照。

成功返回更新后的提案；通过时同时返回新 goal。

## 11. 成就 RPC

### 11.1 `list_achievements`

输入：space_id、limit、cursor。

返回成就类型、获得时间和展示所需 metadata，不返回内部去重键。每个 item 还包含：

```json
{
  "achievement_id": "...",
  "achievement_type": "together_streak",
  "tier": "gold",
  "earned_at": "...",
  "metadata": { "days": 7 },
  "participants_recorded": true,
  "participants": [
    {
      "member_id": "...",
      "display_name": "陈宇",
      "participation_days": 7
    }
  ],
  "seen": true
}
```

`tier = bronze | silver | gold`，前端只使用对应的铜、银、金星星底色和边框，不显示等级文字。`display_name` 是获得成就时的姓名快照；无法可靠回填的旧成就使用 `participants_recorded=false` 和空数组。

### 11.2 `mark_achievement_seen`

成就本身属于友间，已读状态属于成员。输入 achievement_id 和幂等键，只更新当前成员的已读关系，不影响其他成员。

## 12. 设置与房主管理 RPC

### 12.1 `get_space_settings`

权限：活动成员。

返回：

```json
{
  "data": {
    "space": {
      "id": "...",
      "name": "我们的友间",
      "timezone": "Asia/Shanghai",
      "member_limit": 3,
      "daily_checkin_target_minutes": 60,
      "created_at": "..."
    },
    "me": {
      "member_id": "...",
      "display_name": "陈宇",
      "role": "owner",
      "profile_timezone": "Asia/Shanghai"
    },
    "members": [
      {
        "member_id": "...",
        "display_name": "陈宇",
        "role": "owner",
        "status": "active",
        "joined_at": "..."
      }
    ],
    "owner_actions": {
      "can_copy_invite": true,
      "can_rotate_invite": true,
      "can_disable_members": true,
      "can_update_space_name": true,
      "can_increase_member_limit": true
    }
  }
}
```

普通成员的 owner action 均为 false。成员上限达到 12 后，房主的 `can_increase_member_limit=false`。

### 12.2 `update_space_name`

仅房主。输入：space_id、去除首尾空格后 1～30 字的 name、幂等键。成功返回更新后的友间 id 和 name；不会轮换邀请链接，也不会改变历史记录。

错误：`INVALID_SPACE_NAME`、`NOT_SPACE_OWNER`。

### 12.3 `increase_member_limit`

仅房主。输入：space_id、2～12 的 member_limit、幂等键。新值必须严格高于当前上限；成功返回新上限和 `previous_member_limit`，已有邀请链接继续有效。

错误：`INVALID_MEMBER_LIMIT`、`MEMBER_LIMIT_NOT_INCREASED`、`NOT_SPACE_OWNER`。

### 12.4 邀请链接本地生命周期（不提供 `get_current_invite`）

仅房主。由于数据库不保存明文 token，系统不能重新取回旧邀请链接。

因此采用以下明确规则：

- 创建或轮换后的明文链接仅返回给当前房主客户端；
- 客户端只保存在当前浏览器的本地应用存储中，并通过严格 CSP、禁止第三方脚本和输出转义降低泄露风险；
- 若本地链接丢失，房主点击“生成新邀请链接”，实质执行轮换；
- 设置页按钮文案根据本地是否存在链接显示“复制邀请链接”或“生成新邀请链接”。

不提供一个声称能从服务端“读取当前明文邀请”的 RPC。

### 12.5 `rotate_invite`

仅房主。

输入：space_id、幂等键。

成功：

```json
{
  "data": {
    "invite_url": "https://example.com/invite/新token",
    "invite_version": 2
  }
}
```

错误：

- `NOT_SPACE_OWNER`；
- `MEMBER_DISABLED`。

### 12.6 `disable_member`

仅房主。

输入：

```json
{
  "space_id": "...",
  "member_id": "...",
  "idempotency_key": "..."
}
```

成功：

```json
{
  "data": {
    "member": {
      "member_id": "...",
      "status": "disabled",
      "disabled_at": "..."
    },
    "settled_session": null,
    "resolved_proposals": []
  }
}
```

若目标成员有活动 session，`settled_session` 返回其最终权威状态。

错误：

- `NOT_SPACE_OWNER`；
- `CANNOT_DISABLE_OWNER`；
- `MEMBER_NOT_FOUND`；
- `MEMBER_ALREADY_DISABLED`。

## 13. 前端本地状态与 API 映射

| 前端状态 | 触发 | 结束条件 |
|---|---|---|
| `starting` | 调用 `start_focus` | 成功 session 或错误 |
| `pausing` | 调用 `pause_focus` | paused／自动结算／错误 |
| `resuming` | 调用 `resume_focus` | focusing／自动结算／错误 |
| `ending` | 调用 `end_focus` | completed／discarded／错误 |
| `reconciling` | 后台返回、倒计时归零、重连 | `get_home_snapshot` 成功 |
| `realtime_degraded` | 订阅断开但 HTTP 正常 | 订阅恢复并刷新快照 |
| `offline` | 网络请求失败且浏览器提示离线 | 网络恢复后进入 reconciling |

任何写请求网络失败：

- 不改变权威业务状态；
- 不清除本地任务和计时显示；
- 不创建离线命令队列；
- 显示操作尚未生效；
- 恢复后先读取快照，再允许重试。

## 14. 错误码与界面文案

| 错误码 | 用户文案 | 界面处理 |
|---|---|---|
| `INVITE_INVALID` | 这个邀请已失效，请让房主发送新的链接。 | 整页结果 |
| `SPACE_FULL` | 这里已经坐满了。 | 整页结果 |
| `DISPLAY_NAME_TAKEN` | 这个昵称已有人使用。 | 昵称行内错误 |
| `ALREADY_IN_SPACE` | 你已经在这个友间里。 | 回到友间 |
| `ALREADY_IN_ANOTHER_SPACE` | 当前身份已经加入一个友间。 | 展示单身份单友间规则说明 |
| `MEMBER_DISABLED` | 你已不能进入这个友间。 | 清缓存并退出房间 |
| `SESSION_ALREADY_ACTIVE` | 已找到一段正在进行的专注。 | 使用权威 session |
| `SESSION_NOT_FOCUSING` | 专注状态已经变化。 | 使用权威状态 |
| `SESSION_NOT_PAUSED` | 暂停状态已经变化。 | 使用权威状态 |
| `VOTE_ALREADY_FINAL` | 你已经完成选择，不能修改。 | 刷新提案 |
| `GOAL_ALREADY_OPEN` | 当前已有待投票、待开始或进行中的共同目标。 | 保留当前目标，不创建第二份 |
| `NOT_SPACE_OWNER` | 只有房主可以进行这项操作。 | 关闭管理入口 |
| `INVALID_SPACE_NAME` | 友间名称需要包含 1～30 个字符。 | 名称行内错误 |
| `INVALID_MEMBER_LIMIT` | 成员上限需要在 2～12 人之间。 | 上限行内错误 |
| `MEMBER_LIMIT_NOT_INCREASED` | 新上限必须高于当前成员上限。 | 保留当前上限 |
| `INTERNAL_ERROR` | 暂时无法完成操作，请重新加载。 | 保留当前安全状态 |

网络失败不使用业务错误码。统一文案必须包含“操作是否生效”和“计时是否继续”。

## 15. API 安全检查

- RPC 内部从 `auth.uid()` 获取用户，不接受客户端 actor_id；
- 所有 space_id、session_id、member_id 均重新验证成员关系；
- SECURITY DEFINER 函数固定 `search_path`；
- public preview 只接受 token，不接受可枚举 space_id；
- 邀请 token 和 Auth token 不写日志；
- 所有写 RPC 做参数长度和枚举校验；
- 返回结构不泄露其他房间 ID；
- Realtime payload 只作为刷新提示；
- 错误差异不能用于枚举私人房间；
- 房间人数检查、昵称唯一检查和加入写入在同一事务完成。

## 16. 契约测试清单

### 通用

- [ ] 每个响应包含 request_id 和 server_now；
- [ ] 重复幂等键返回相同结果；
- [ ] 相同键不同参数被拒绝；
- [ ] 数据库异常不直接暴露；
- [ ] 未授权 ID 不泄露实体是否存在。

### 邀请与成员

- [ ] 未登录用户只能读取邀请预览白名单字段；
- [ ] 邀请失效、已满和昵称占用返回不同业务结果；
- [ ] 并发加入不会超过人数上限；
- [ ] 停用成员无法重新用旧 token 恢复原身份；
- [ ] 房主明文邀请丢失时通过轮换恢复，而非服务端解密。

### 计时

- [ ] 所有计时 RPC 返回统一 session 结构；
- [ ] 到期恢复返回自动结算结果；
- [ ] Cron 抢先结算后 end 仍返回已有最终状态；
- [ ] 网络失败不产生离线操作；
- [ ] 心跳不能延长、暂停或结束 session；
- [ ] Realtime 乱序不会使 UI 状态倒退。

### 统计与目标

- [ ] 统计响应明确使用的时区和周期边界；
- [ ] discarded 不进入聚合；
- [ ] history 分页稳定且不重复；
- [ ] 发起人自动接受；
- [ ] 投票不可修改；
- [ ] 最后一票和目标创建在同一事务完成。

## 17. 已冻结产品决策映射

### 每日打卡门槛

MVP 所有示例和服务端配置使用 60 分钟。最终值来自 `spaces.daily_checkin_target_minutes`，不是前端常量。

### 单身份友间数量

`get_my_membership` 返回单个活动成员对象，`join_space` 在已有活动友间时返回 `ALREADY_IN_ANOTHER_SPACE`。

若允许多个友间：

- 改为 `list_my_memberships`；
- 首页路由必须始终包含 space_id；
- `start_focus` 仍要求明确 space_id；
- 当前技术默认一条 session 只属于一个友间，不跨房间广播。

## 18. 契约冻结标准

- [ ] 页面所需的每个读取状态都有对应查询；
- [ ] 每个用户操作都有对应命令；
- [ ] 命令成功、业务冲突和网络失败语义不同；
- [ ] 所有计时命令返回同一权威 session 结构；
- [ ] Realtime 不承担唯一数据来源；
- [ ] 邀请明文的生命周期无未定义环节；
- [ ] 统计周期、时区和单位明确；
- [ ] 两项待决策均集中映射且可配置。
