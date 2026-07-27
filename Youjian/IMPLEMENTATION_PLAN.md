# 友间（Youjian）MVP 实施计划

> 输入规格：[MVP_SPEC.md](./MVP_SPEC.md)、[UI_STATE_SPEC.md](./UI_STATE_SPEC.md)、[WIREFRAME_SPEC.md](./WIREFRAME_SPEC.md)、[TECHNICAL_DESIGN.md](./TECHNICAL_DESIGN.md)、[API_CONTRACT.md](./API_CONTRACT.md)  
> 目标：按照依赖顺序完成可部署、可验证的 MVP，而不是先做外观再补计时一致性。  
> 已冻结规则：每日打卡 60 分钟；一个匿名身份只加入一个友间。

## 1. 实施原则

- 数据库不变量先于页面交互；
- 每个里程碑必须有独立可验证的退出条件；
- 不以手工演示代替并发、权限和时间边界测试；
- 客户端不实现服务端已有的权威计算；
- 主流程完成前不增加聊天、排行榜、推送或任务清单；
- 所有迁移可从空数据库重复执行；
- 所有环境变量均通过示例文件说明，真实密钥不进入 Git；
- 每完成一个纵向流程，就在两台真实移动设备上验证。

## 2. 阶段总览

| 阶段 | 结果 | 依赖 | 退出门槛 |
|---|---|---|---|
| M0 | 工程与本地环境可运行 | 无 | CI 和本地 smoke test 通过 |
| M1 | 数据库基础、Auth、RLS | M0 | 权限测试通过 |
| M2 | 创建、邀请、加入 | M1 | 两台设备进入同一友间 |
| M3 | 权威计时状态机 | M2 | 时间边界与并发测试通过 |
| M4 | 首页、Realtime、连接状态 | M3 | 双设备实时流程通过 |
| M5 | 跨日统计与连续打卡 | M3 | 时区测试通过 |
| M6 | 共同目标与成就 | M5 | 提案周期测试通过 |
| M7 | 设置、PWA、无障碍 | M2–M6 | 安装和管理流程通过 |
| M8 | 安全、性能、发布 | 全部 | 发布检查全部通过 |

M3 是最高风险阶段，不得被 UI 进度掩盖。

## 3. M0：工程基础

### 3.1 产物

```text
package.json
vite.config.ts
tsconfig*.json
eslint.config.*
src/
public/
supabase/
├── config.toml
├── migrations/
├── seed.sql
└── tests/
.env.example
.gitignore
README.md
```

### 3.2 前端初始化

- React + TypeScript + Vite；
- React Router；
- TanStack Query；
- Supabase JS；
- Zod；
- PWA 插件先安装但暂不启用离线缓存；
- ESLint、TypeScript strict、格式化规则；
- 单元测试与浏览器端测试框架；
- 移动端 viewport 与安全区基础样式。

### 3.3 环境变量

`.env.example` 只列名称：

```text
VITE_SUPABASE_URL=
VITE_SUPABASE_PUBLISHABLE_KEY=
VITE_APP_ORIGIN=
```

禁止出现：

- service role key；
- 数据库密码；
- 邀请 token；
- 生产 Auth token。

### 3.4 CI 基线

每次提交运行：

1. 依赖锁文件一致性安装；
2. TypeScript 类型检查；
3. ESLint；
4. 单元测试；
5. production build；
6. 数据库迁移静态检查。

### 3.5 退出条件

- [ ] 本地一条命令启动前端；
- [ ] 本地 Supabase 可以初始化和重建；
- [ ] 空页面在 320px 和桌面尺寸无横向滚动；
- [ ] CI 全绿；
- [ ] `.env.example` 完整且无密钥。

## 4. M1：数据库、Auth 与权限

### 4.1 迁移拆分

建议按不可逆依赖排序：

```text
0001_extensions_and_enums.sql
0002_profiles_spaces_members.sql
0003_focus_tables.sql
0004_goal_and_achievement_tables.sql
0005_indexes_and_constraints.sql
0006_rls_and_grants.sql
0007_rpc_shared_helpers.sql
0008_cron_jobs.sql
```

开发中可以追加迁移，禁止修改已经用于共享环境的历史迁移。

### 4.2 数据库 helper

优先实现：

- `current_user_is_active_member(space_id)`；
- `current_user_is_owner(space_id)`；
- `validate_iana_timezone(text)`；
- `normalize_display_name(text)`；
- `make_response(data/error)`；
- `claim_idempotency_key(...)`；
- `record_focus_event(...)`。

所有 `security definer` helper 固定 `search_path`，默认不授予 public execute。

### 4.3 Auth

- 启用 Anonymous Sign-In；
- 配置 CAPTCHA／Turnstile；
- 验证前端只使用 publishable key；
- 创建匿名用户后由受控 RPC 初始化 profile；
- 不运行匿名用户自动清理任务。

### 4.4 权限测试先行

在业务页面出现前写出：

- 非成员读取失败；
- 跨房间读取失败；
- 普通成员管理失败；
- 直接写核心表失败；
- RPC 只能操作本人 session；
- 停用后读取立即失败。

### 4.5 退出条件

- [ ] 所有公开表启用 RLS；
- [ ] 直接 INSERT/UPDATE/DELETE 核心表被拒绝；
- [ ] 安全函数的 search_path 已固定；
- [ ] 跨用户、跨房间权限测试通过；
- [ ] 数据库 reset 后测试可重复通过。

## 5. M2：创建、邀请与加入

### 5.1 服务端顺序

1. `get_my_membership`；
2. `get_invite_preview`；
3. `create_space`；
4. `join_space`；
5. `rotate_invite`；
6. 邀请预览速率限制。

### 5.2 前端顺序

1. 欢迎页；
2. 匿名 Auth bootstrap；
3. 创建表单；
4. 邀请预览；
5. 加入表单；
6. 成员路由守卫；
7. 邀请失效、已满、昵称冲突和停用结果页。

### 5.3 必须验证的竞争条件

- 两人同时抢最后一个位置，只能一个成功；
- 同一用户双击创建只产生一个友间；
- 同一用户重复加入返回已有成员；
- 房主轮换 token 后旧 token 立即失效；
- 大小写和首尾空格不能绕过昵称唯一约束。

### 5.4 双设备验收

设备 A：创建“我们的友间”，复制邀请。  
设备 B：打开链接，预览后用不同昵称加入。  
A、B：刷新、关闭再打开后仍恢复各自身份和成员关系。

### 5.5 退出条件

- [ ] 创建和加入主流程通过；
- [ ] 所有邀请异常状态有界面；
- [ ] 加入前看不到房间私密数据；
- [ ] 明文 token 不出现在数据库和日志；
- [ ] 身份不可恢复警告在三个规定位置出现。

## 6. M3：权威计时状态机

### 6.1 实现顺序

1. `focus_sessions` 约束和活动记录部分唯一索引；
2. `focus_segments`；
3. `focus_events`；
4. 幂等命令表；
5. `start_focus`；
6. `pause_focus`；
7. `resume_focus`；
8. `end_focus`；
9. `settle_session`；
10. `run_minute_maintenance`。

### 6.2 测试时钟

生产函数使用 `now()`。为测试提供受限的内部 helper 或事务级固定时间，不允许普通客户端传入“当前时间”。

推荐测试表格：

| 场景 | 起点 | 操作 | 期望 |
|---|---|---|---|
| 不足门槛 | 00:00 | 04:59 结束 | discarded 299s |
| 达到门槛 | 00:00 | 05:00 结束 | completed 300s |
| 正常暂停 | 00:00 | 20:00 暂停 | accumulated 1200s |
| 及时恢复 | 暂停 00:00 | 14:59 恢复 | focusing |
| 暂停超时 | 暂停 00:00 | 15:00 恢复 | 自动结算 |
| 多段累计 | 30m + pause + 30m | 结束 | 3600s |
| 六小时 | 已累计 5h50m | 再专注 10m | 精确截断 6h |
| Cron 延迟 | 6h 到期后 4m 执行 | 自动结算 | 仍为 21600s |

### 6.3 并发测试

- start × 2；
- pause × 2；
- resume 与暂停超时 Cron；
- end 与六小时 Cron；
- 两个浏览器标签页进行相反操作；
- 成员停用与主动结束。

每个场景验证：

- 最终状态唯一；
- open segment 数量合法；
- accumulated 与 segments 总和一致；
- completed 事件只有一个；
- 重试返回相同结果。

### 6.4 退出条件

- [ ] 全部时间边界测试通过；
- [ ] 全部并发测试通过；
- [ ] 客户端无法直接写累计秒数；
- [ ] 已结算记录无法修改或删除；
- [ ] Cron 晚运行不改变最终时间。

## 7. M4：首页、实时同步与连接状态

### 7.1 首页垂直切片

先实现以下最小闭环：

```text
get_home_snapshot
→ idle 首页
→ 开始抽屉
→ focusing 卡片
→ 好友设备收到变化
→ pause/resume/end
→ 结算卡
```

### 7.2 Realtime

- 订阅只作为 query invalidation；
- 使用实体 version 忽略旧事件；
- 重连后完整刷新 snapshot；
- 页面从后台返回后先进入 reconciling；
- 不让本地每秒 timer 写入 React Query 缓存。

### 7.3 心跳

- focusing 前台每 45 秒；
- 120 秒无心跳标记 unconfirmed；
- 重新可见立即心跳并读取快照；
- 心跳失败不暂停 session；
- 不显示确定的“网络断开原因”。

### 7.4 双设备场景

- A 开始，B 数秒内看到；
- A 暂停，B 的 A 卡片移除；
- A 恢复，卡片重新出现且时间不含暂停；
- A 锁屏，B 看到最后同步时间；
- A 返回，连接提示消失；
- A 离线点击结束，不显示成功；
- 网络恢复后先同步，再允许结束。

### 7.5 退出条件

- [ ] 主状态机所有 UI 状态可达；
- [ ] 网络失败不伪造成功；
- [ ] Realtime 乱序不倒退状态；
- [ ] 计时显示与服务器校准误差可控；
- [ ] iOS 和 Android 后台返回流程通过。

## 8. M5：统计与连续打卡

### 8.1 服务端

1. segment 与本地日范围求交函数；
2. `get_stats_summary`；
3. `list_focus_history`；
4. `get_focus_session_detail`；
5. streak 计算；
6. 统计索引和查询计划检查。

### 8.2 必测时区

- `Asia/Shanghai`：无夏令时；
- `Europe/Paris`：夏令时开始和结束；
- `America/New_York`：与房间跨日不同；
- UTC：基准。

### 8.3 边界场景

- 23:50–00:20 跨日；
- 周日跨到周一；
- 月末跨到下月；
- 夏令时 23 小时日；
- 夏令时 25 小时日；
- discarded 跨日仍全部排除；
- 当前未结算 session 不提前完成正式打卡；
- 停用成员历史仍可见。

### 8.4 前端

- 我的／友间切换；
- 日／周／月切换；
- 空数据和只有无效记录；
- 历史游标分页；
- session 详情抽屉；
- 时区说明；
- 连接状态不可确认标记。

### 8.5 退出条件

- [ ] 跨日、跨周、跨月结果正确；
- [ ] 夏令时测试正确；
- [ ] 连续打卡只由已结算有效记录触发；
- [ ] 个人和友间使用各自时区；
- [ ] 查询在预期数据量下响应稳定。

## 9. M6：共同目标与成就

### 9.1 提案

- 发起人自动接受；
- 创建时冻结投票成员；
- 任何拒绝立即结束；
- 48 小时过期；
- 最后一票和 scheduled goal 同一事务；
- pending 时停用成员后重算；
- 新成员不加入旧提案。

### 9.2 目标

- 按房间时区确定下一完整周期；
- 通过时冻结参与成员；
- scheduled → active → completed/failed；
- 三种目标分别测试；
- 已完成目标不因后续数据变化回退。

### 9.3 成就

- 去重键唯一；
- 服务器授予；
- 每位成员独立已读；
- 动画只播放一次；
- 减少动态效果时禁用动画。

### 9.4 退出条件

- [ ] 提案所有状态可达；
- [ ] 投票不能修改；
- [ ] 成员变化规则按快照执行；
- [ ] 三类目标计算正确；
- [ ] 成就不会重复授予或重复弹出。

## 10. M7：设置、PWA 与无障碍

### 10.1 设置

- 成员列表；
- 房主操作权限；
- 邀请复制／重新生成；
- 停用成员及活动 session 结算；
- 身份不可恢复警告；
- 版本和隐私说明。

### 10.2 PWA

- manifest 名称、短名称、主题色和图标；
- standalone 显示；
- iOS 手动安装说明；
- 静态 app shell 缓存；
- API network-only；
- 新版本提示，不在计时中强制刷新；
- 离线启动显示缓存外壳和不可确认状态。

### 10.3 无障碍

- 44×44 点击区域；
- 键盘完整流程；
- `aria-live` 只播报关键状态；
- 200% 字体缩放；
- 不只依赖颜色；
- 减少动画；
- 安全区和虚拟键盘测试。

### 10.4 退出条件

- [ ] iOS Safari 和 Android Chrome 可添加桌面；
- [ ] API 响应不进入 Service Worker 缓存；
- [ ] 房主和成员看到正确管理入口；
- [ ] 核心流程通过键盘和屏幕阅读器 smoke test；
- [ ] 320px 无关键横向滚动。

## 11. M8：发布准备

### 11.1 安全

- RLS 全量复测；
- 邀请接口限速；
- CSP 禁止未知脚本；
- 不记录任务、昵称和 token；
- source map 访问策略确认；
- service role key 扫描；
- 数据库函数 execute 权限审计；
- 生产 CAPTCHA 配置。

### 11.2 数据与恢复

- 自动数据库备份设置确认；
- 至少执行一次恢复演练；
- 迁移在生产副本环境验证；
- Cron 失败告警；
- 不自动清理匿名用户；
- 明确测试数据与生产数据隔离。

### 11.3 性能预算

目标而非虚假保证：

- 首屏压缩 JS 尽量低于 200KB；
- 首页正常网络下 2 秒内出现可用骨架或内容；
- 常用 RPC 数据库执行时间 p95 低于 300ms；
- Realtime 更新正常情况下数秒内可见；
- 首页 snapshot 不返回完整历史。

### 11.4 浏览器矩阵

- iOS Safari 当前主流版本；
- Android Chrome 当前主流版本；
- 桌面 Chrome、Edge、Safari；
- PWA standalone 和普通浏览器各测一次。

### 11.5 生产 smoke test

1. 新设备创建友间；
2. 第二台设备加入；
3. 两人开始不同任务；
4. 暂停、恢复和结束；
5. 锁屏返回；
6. 查看统计；
7. 提交并投票共同目标；
8. 轮换邀请；
9. 验证旧邀请失效；
10. 安装 PWA 并重新打开。

### 11.6 发布门槛

- [ ] 所有阶段退出条件完成；
- [ ] 数据库、RLS 和 E2E 测试全绿；
- [ ] 两台真实设备 smoke test 通过；
- [ ] 无 P0/P1 缺陷；
- [ ] 备份、Cron 和错误监控可见；
- [ ] 隐私说明和身份丢失说明已上线。

## 12. 测试数据

本地 seed 提供：

- 1 个房主、2 个成员；
- 1 个已停用成员；
- focusing、paused、completed、discarded 各一条；
- 一条跨午夜记录；
- 一条连接状态不可确认记录；
- pending、scheduled、active、completed、failed 目标；
- 至少两个成就。

测试昵称和任务均使用明显虚构内容，禁止从真实用户数据复制。

## 13. 缺陷优先级

### P0

- 跨房间数据泄露；
- 可以修改他人或历史时长；
- 重复 session 导致统计污染；
- Auth／邀请 token 泄露；
- 数据库迁移导致不可恢复的数据丢失。

### P1

- 计时或跨日统计错误；
- 自动结算错误；
- 网络失败被显示为操作成功；
- 停用成员仍可访问；
- 共同目标错误授予。

### P2

- Realtime 延迟但刷新可恢复；
- PWA 安装提示异常；
- 部分空状态或错误文案缺失；
- 小屏布局问题但主流程仍可完成。

### P3

- 动画、间距或非关键视觉细节；
- 不影响结果的显示秒级误差。

发布前必须清零 P0/P1。

## 14. 风险登记

| 风险 | 影响 | 概率 | 缓解 |
|---|---|---|---|
| 移动系统冻结 PWA | 连接状态误判 | 高 | 服务端计时、后台返回核对 |
| 匿名身份丢失 | 用户无法恢复 | 中 | 三处明确警告、不提供退出按钮 |
| 邀请链接泄露 | 非预期加入 | 低 | 人数上限、房主轮换、token hash |
| Cron 延迟 | UI 晚看到自动结算 | 中 | 精确截断、惰性结算 |
| Realtime 乱序 | UI 状态倒退 | 中 | version + 完整快照 |
| 时区／夏令时 | 统计错误 | 中 | segment 求交和专门测试 |
| 目标成员变化 | 规则争议 | 中 | 提案和参与者快照 |
| 匿名用户滥用 | 数据库膨胀 | 低 | CAPTCHA、限速、不公开传播 |

## 15. 明确延后

以下内容不得混入上述里程碑：

- 多友间导航；
- 身份绑定邮箱或跨设备恢复；
- 消息推送；
- 聊天与视频；
- 自定义分类；
- 任务清单；
- 排行榜；
- 手动补录；
- 修改历史；
- 原生 App；
- TickTick／滴答清单接口。

## 16. 已确认规则对实施的约束

### 每日打卡门槛

`spaces.daily_checkin_target_minutes` 固定为 60，M5 统计、打卡、共同出勤和测试数据均按此断言。

### 单身份友间数量

M2 的 `join_space` 必须执行单身份单友间服务端规则；数据库不增加会永久阻止未来扩展的全局唯一约束。

## 17. 实施完成定义

“页面能点”不等于完成。MVP 完成必须同时满足：

- 五份设计规格与实现一致；
- API 契约中的 RPC 均已实现并通过契约测试；
- 状态规格中的核心、异常和权限状态可验证；
- 线框中的 16 个原型状态均有对应页面结果；
- 数据库时间、权限和并发测试通过；
- 两台真实移动设备完成端到端流程；
- PWA 安装、后台恢复和版本更新通过；
- 发布检查、备份和监控完成；
- 两项已冻结决策已经写回所有权威文档并落实为测试断言。
