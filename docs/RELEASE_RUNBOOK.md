# 友间发布与恢复运行手册

本文件定义 M8 所需的操作证据。未填写结果和负责人签字的项目不得视为已通过。

## 1. 环境隔离

| 环境 | Supabase 项目 | 前端域名 | CAPTCHA | 测试数据 | 已核验 |
|---|---|---|---|---|---|
| Local | 本地 CLI | `127.0.0.1` | Cloudflare 官方测试密钥，服务端强制 | 允许虚构 seed | 是 |
| Staging | 待配置 | 待配置 | 按部署模式选择 | 仅虚构数据 | 否 |
| Production | 待配置 | 待配置 | 小范围可信成员可关闭 | 禁止测试 seed | 否 |

生产环境不得复用 local/staging 密钥、数据库或 Auth 用户。不得启用匿名用户自动清理。

本项目允许两种 CAPTCHA 模式：公开或可能被传播的邀请必须启用 Turnstile；仅供固定好友使用的小范围部署可以同时省略前端 `VITE_TURNSTILE_SITE_KEY` 并关闭 Supabase Auth CAPTCHA。关闭 CAPTCHA 不得关闭邀请接口限速、RLS、成员上限或单身份单友间约束。

## 2. 发布前自动验证

```powershell
npm ci
npm run format:check
npm run typecheck
npm run lint
npm run security:scan
npm run security:audit
npm test
npm run build
npm run release:verify
npm run db:start
npm run db:reset
npm run test:e2e
npm run db:lint
npm run db:test
npm run test:integration
npm run test:performance
npm run test:performance:scale
npm run ops:monitor-check
npm run ops:monitor-alert-drill
npm run ops:monitor-check
npm run ops:restore-drill
npm run db:test
```

记录 CI URL、commit SHA、浏览器版本和执行日期。

## 3. 备份与恢复演练

1. 确认生产自动备份策略、保留周期和恢复点目标。
2. 从 staging 或经过脱敏的生产副本生成备份。
3. 恢复到隔离的临时项目，禁止覆盖 local/staging/production。
4. 从空库运行全部迁移，然后恢复允许恢复的数据。
5. 核对成员数、session 数、segment 累计、目标与成就去重键。
6. 运行数据库测试和十步 smoke test。
7. 记录备份 ID、目标项目、开始/结束时间、校验结果和执行人。

| 日期 | 备份 ID | 隔离恢复目标 | 校验摘要 | 执行人 | 结果 |
|---|---|---|---|---|---|
| 2026-07-28 | schema `1eb877b6b1e6…` / data `171b88b8f358…` | 独立全新 PostgreSQL 容器 `youjian_restore_7f28b7c848d1` | 恢复 `auth`、`private`、`public`、`supabase_migrations`；52 个 Auth 用户、10,021 个 session、20,033 个 segment 及所有表逐表计数一致；迁移 26、Cron 1、Realtime 表 5；ACL/RLS/secret/RPC 完整且不安全 helper execute 为 0；恢复后 13 个 pgTAP 文件全部通过 | Codex 本地自动化 | 通过（仅本地） |

## 4. Cron 与错误监控

- `run_minute_maintenance()`：每分钟执行；监控处理数、耗时、失败数。
- 告警条件：连续两次失败、单次超过 50 秒、待结算记录持续增长。
- 日志只记录 request ID、内部实体 ID、稳定错误码和状态转换；不得记录昵称、任务、邀请 token 或 Auth token。
- 至少演练一次 Cron 失败告警与一次前端错误采集，记录告警到达时间。

本地已验证 Cron 运行审计与脱敏前端错误事件可持久化且客户端不能读取私有表；`ops:monitor-check` 是被动探针，会校验任务启用状态、调度表达式和命令、真实 `cron.job_run_details`、Cron 来源审计、运行间隔、连续失败、50 秒慢任务及待结算积压，不会自行运行维护来掩盖调度故障。`ops:monitor-alert-drill` 已通过本地 HTTP webhook 验证“停用 Cron → 健康检查失败 → 告警送达 → 恢复 Cron”；staging/production 仍需配置真实外部告警提供商并记录到达证据。

## 5. 性能测试条件

- 首页：中档移动设备、正常 4G 模拟，2 秒内出现可用骨架或内容。
- JavaScript：最大首屏文件 gzip 小于 200 KiB，由 `release:verify` 强制。
- RPC：staging 使用至少 12 个成员、10,000 条 session、20,000 条 segment；常用 RPC p95 小于 300 ms。
- Realtime：同区域两台设备，正常网络下状态数秒内可见。
- `get_home_snapshot` 不得包含完整历史列表。

2026-07-28 本地 40 次 `get_home_snapshot` 采样：p50 6.7 ms，p95 11.8 ms；这不是 staging 数据量下的生产性能证明。

2026-07-28 从洁净库执行完整序列后的本地规模夹具（10,000 个 session、20,000 个 segment）结果：首页 p95 51.8 ms、月统计 p95 31.6 ms、历史分页 p95 8.4 ms，均低于 300 ms。最终发布回归在累积测试数据上复测：首页 p95 118.2 ms、月统计 p95 39.4 ms、历史分页 p95 16.2 ms。另有 pgTAP 规模测试同时加入 10,000 个目标房间 session 和 10,000 个其他房间干扰 session，验证首页和月统计仍低于 300 ms。该结果验证房间级查询计划和回归门禁，不替代 staging/production 容量测试。

## 6. 浏览器与真实设备矩阵

| 平台 | 版本 | Browser | PWA standalone | 日期 | 结果 |
|---|---|---|---|---|---|
| iPhone | 待填 | Safari | 待测 | — | 未验证 |
| Android | 待填 | Chrome | 待测 | — | 未验证 |
| Windows | 150.0.7871.182 | Chrome | 不适用 | 2026-07-28 | 最新四项目矩阵合计 34 通过 / 2 按能力跳过 |
| Windows | 150.0.4078.99 | Edge | 不适用 | 2026-07-28 | Playwright 23 通过 / 1 跳过 |
| macOS | 待填 | Safari | 不适用 | — | 未验证 |

自动化补充证据：320px Chromium、桌面 Chromium、Pixel 7 Chromium 与 iPhone 13 WebKit 四项目矩阵合计 34 项通过、2 项按能力跳过；包含 200% 文本、小高度虚拟键盘视口、Turnstile widget → 匿名 Auth 服务端校验 → 创建友间，以及两个独立浏览器上下文创建、邀请、加入、实时计时和重载恢复身份。WebKit 验证 Service Worker 注册和激活；真正断网的外壳缓存/API NetworkOnly 由 Chromium 项目验证。仿真结果不计作真实设备验收。

## 7. 生产 smoke test

- [ ] 新设备创建友间。
- [ ] 第二台设备通过邀请加入。
- [ ] 两位成员开始不同任务。
- [ ] 暂停、恢复和结束结果正确。
- [ ] 锁屏返回后先同步再允许操作。
- [ ] 日／周／月统计正确。
- [ ] 提交并全员通过共同目标。
- [ ] 房主轮换邀请。
- [ ] 旧邀请立即失效。
- [ ] 安装 PWA 并重新打开后恢复匿名身份。

## 8. 发布签字

只有数据库/RLS/E2E 全绿、P0/P1 为零、备份恢复与告警演练有证据、隐私与身份说明上线后才可发布。
