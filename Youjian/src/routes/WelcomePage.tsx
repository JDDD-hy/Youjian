import { Link } from 'react-router-dom';

function LampMark() {
  return (
    <div className="lamp-mark" aria-hidden="true">
      <span className="lamp-mark__shade" />
      <span className="lamp-mark__stem" />
      <span className="lamp-mark__base" />
      <span className="lamp-mark__glow" />
    </div>
  );
}

export function WelcomePage() {
  return (
    <main className="welcome-shell">
      <section className="welcome-card" aria-labelledby="welcome-title">
        <LampMark />
        <p className="eyebrow">共享专注空间</p>
        <h1 id="welcome-title">友间</h1>
        <p className="tagline">在友间，自有间。</p>
        <p className="welcome-copy">
          和固定好友共享专注状态，保留各自的节奏，也陪伴彼此点亮时间。
        </p>
        <Link className="primary-action" to="/create">
          创建友间
        </Link>
        <p className="identity-note">
          无需注册账号。匿名身份只保存在当前设备中。
        </p>
      </section>
    </main>
  );
}
