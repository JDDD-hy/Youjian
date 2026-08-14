# 新增成就测试矩阵

目录源文件是 `src/domain/achievementCatalog.json`；数据库迁移保存同版本的 enforcement snapshot。测试不重算历史数据，所有新成就 fixture 都使用独立用户、独立友间、独立 session 和固定事件时间。

## 测试层级

| 层级 | 目标 | 复用入口 | 必须验证 |
|---|---|---|---|
| L0 纯规则 | 不触碰数据库地验证目录、阶段、颜色、名称、read target | `src/domain/achievementCatalog.test.ts`、`src/domain/achievementContract.test.ts` | key 唯一、阈值、阶段上限、全球 Silver/Gold、万时户 Diamond、契约字段 |
| L1 pgTAP | 验证数据库 recorder、激活边界、历史保留、通知与 RLS | `supabase/tests/027_achievement_strategy_catalog.sql` | 目录快照、一次性/系列、重复通知、600000 分钟、个人列表 |
| L2 集成 | 走真实 Supabase RPC 和数据库触发器 | `scripts/integration/achievement-fixture.mjs` | 独立身份、真实 start/end/update/membership 路径、固定时钟注入、RPC 展示字段 |
| L3 浏览器 | 验证真实页面卡片、标题、图标、已读路径 | 现有 Playwright harness + L2 fixture | 页面展示、共享卡片 read target、个人 tab read target、部署 bundle |

## 新增成就矩阵

| 成就 | 正向案例 | 边界 / 对抗案例 | 写入与通知预期 | 首要层级 |
|---|---|---|---|---|
| 天涯共此时 | 同一重叠事件含 2 个不同 IANA 时区 | 1 个时区不达成；同一时区多成员不重复；并发完成不能丢 stage | Silver unlock；历史 event 保留 | L1/L2 |
| 五湖四海 | 同一重叠事件含 4 个不同 IANA 时区 | 3 个不达成；4 个升级 Gold；升级后重复不通知 | Gold stage upgrade；重复 durable event 保留 | L1/L2 |
| 精雕细琢 | 同一任务 3 次成功改名 | no-op 不计；其他成员 actor 不计；不同任务不合并 | 仅第 3 次一次性 Gold | L1/L2 |
| 一锤定音 | 无改名、有效专注 ≥60 分钟 | 59:59 不达成；暂停可恢复；任意 task name update 取消资格 | 一次性 Gold | L2 首个 E2E |
| 如坐针毡 | 3 次有效时长 1～299 秒 | 0 秒不计；正好 300 秒不计；discarded 短 session 可计入 | 第 3 次一次性 Gold | L1/L2 |
| 兢兢业业 | 最终 category=work 的有效完成 session 10 次 | 9 次不达成；改成其他类型按最终类型计；discarded 不计 | 一次性 Gold | L1 |
| 学海无涯 | 最终 category=study 的有效完成 session 10 次 | 9 次不达成；类别混合不串计数 | 一次性 Gold | L1 |
| 书虫 | 最终 category=reading 的有效完成 session 10 次 | 9 次不达成；类别混合不串计数 | 一次性 Gold | L1 |
| 神秘事务 | 最终 category=other 的有效完成 session 10 次 | 9 次不达成；非法类别不能写入 | 一次性 Gold | L1 |
| 周末战士 | 用户本地周六 00:00 至周一 00:00 累计 240 分钟 | 239 分钟不达成；周五/周一边界不串周；DST 前后均按本地午夜 | 一次性 Gold | L1/L2 |
| 万时户 | 终身有效专注达到 600000 分钟 | 599999 不达成；超阈值仍只一次；直接 Diamond | 一次性 Diamond | L1 |
| 虚左以待 | 第一个新成员成功加入 | 非 owner 不授予；重复加入/禁用成员不计；历史成员不回补 | owner 一次性 Gold | L1/L2 |
| 高朋满座 | 当前 active 成员达到 member_limit 且 ≥5 | 4 人不达成；未到容量不达成；只授予 owner | owner 一次性 Gold | L1/L2 |

## 隔离夹具约束

`achievement-fixture.mjs` 提供：

- 独立匿名 Supabase client 与内存 storage，避免复用真实身份；
- `randomKey()` 生成每次运行独立的 idempotency key；
- `setFocusClock()` 只调整测试 session 的有效片段时钟，不改变 rollout 后的 session `started_at`，确保激活边界仍走真实规则；
- `superuserSql()` 仅用于本地测试时钟/断言，不作为生产业务写入替代；
- 每个案例使用独立空间，运行前由 `supabase db reset` 提供干净数据库。

首个端到端案例是“一锤定音”：真实 `start_focus` → 夹具推进有效片段时钟 → 真实 `end_focus` → trigger/recorder → `list_personal_achievements` 与 `get_home_snapshot`，并断言一次性 Gold、无 `task_updated`、`personal_tab` read target。

首个案例的浏览器断言由同一脚本继续执行：启动构建产物，注入夹具产生的匿名会话，真实打开 `/space/:spaceId/goals`，断言“一锤定音”卡片、Gold 样式、Gavel 图标和 `mark_achievement_tab_seen` 请求。

发布前必须同时通过 L0/L1/L2/L3；L1 还覆盖无 JWT 的 scheduled-maintenance 标记、周五跨周六窗口和“分类变化不算改名”的边界。
