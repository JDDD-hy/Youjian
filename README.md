# 友间（Youjian）

友间是面向固定好友的小型共享专注空间。成员继续使用各自的任务管理工具，友间只记录专注任务、实时状态、累计时长、连续打卡和共同目标。

> 在友间，自有间。

## 当前阶段

项目已完成 MVP 产品与技术设计冻结，正在进行视觉设计。首版移动端视觉方向稿已生成，尚未开始业务代码实现。

## 文档地图

按以下顺序阅读：

1. [MVP_SPEC.md](./MVP_SPEC.md)：产品范围、业务规则与验收标准；
2. [UI_STATE_SPEC.md](./UI_STATE_SPEC.md)：页面状态、交互、异常和文案；
3. [WIREFRAME_SPEC.md](./WIREFRAME_SPEC.md)：移动端／桌面端布局和组件；
4. [TECHNICAL_DESIGN.md](./TECHNICAL_DESIGN.md)：数据库、状态机、权限、统计和 PWA；
5. [API_CONTRACT.md](./API_CONTRACT.md)：前后端 RPC 输入、输出和错误语义；
6. [IMPLEMENTATION_PLAN.md](./IMPLEMENTATION_PLAN.md)：开发里程碑、测试门槛和发布检查。
7. [VISUAL_DESIGN.md](./VISUAL_DESIGN.md)：视觉方向、色彩、字体和组件外观。

视觉预览：[design/youjian-visual-direction-v1.png](./design/youjian-visual-direction-v1.png)

## 已确定的核心规则

- 长期存在的友间与单次专注记录分开；
- 只填昵称，底层使用 Supabase Anonymous Auth；
- 匿名身份绑定当前设备，清除数据或换设备后无法恢复；
- 开始后任务内容不可修改；
- 暂停不累计时长，暂停满 15 分钟自动结算；
- 单次实际专注满 6 小时自动结算；
- 单次少于 5 分钟保留记录但不计入统计；
- 关闭网页、锁屏或断网时计时继续；
- 无法确定断线原因时统一标记“连接状态不可确认”；
- 历史记录不可修改或删除；
- 个人统计按个人时区，共同统计按房间时区；
- 共同目标需要提案成员一致接受后才生效；
- 不接入 TickTick／滴答清单私有接口。

## 已冻结决策

1. 每日累计 60 分钟完成个人打卡；
2. MVP 一个匿名身份只能加入一个友间。

所有设计、数据库规则、接口和实施计划均已同步。数据库保留未来扩展能力，但 MVP 必须执行以上规则。

## 推荐技术栈

- React + TypeScript + Vite；
- Supabase Anonymous Auth；
- PostgreSQL + RLS + RPC；
- Supabase Realtime；
- Supabase Cron；
- PWA。

## 非 MVP

任务清单、聊天、视频、排行榜、推送、多设备恢复、手动补录、历史修改、原生 App 和 TickTick 私有接口均不属于首版。

## 本地开发

### 独立环境

项目使用独立 Conda 环境 `youjian`，不复用其他 Python/Conda 环境：

```powershell
conda env create --file environment.yml --solver classic
conda activate youjian
npm ci
```

环境已经存在时跳过第一条命令。当前机器上的环境位于 `D:\Anaconda\envs\youjian`。

Node.js 依赖全部安装在项目目录。Supabase CLI 也是项目级开发依赖，通过 npm script 调用。

### 启动

Docker Desktop 运行后启动本地 Supabase，再启动前端：

```powershell
npm run db:start
npm run dev
```

复制 `.env.example` 为 `.env.local`，并填入 `npm run db:start` 输出的本地 URL 与 publishable key。真实密钥不得提交。

### 验证

```powershell
npm run typecheck
npm run lint
npm test
npm run build
npm run db:reset
npm run db:lint
```

本地浏览器 smoke test 使用已安装的 Google Chrome，运行 `npm run test:e2e`。CI 使用 Playwright 管理的 Chromium。
