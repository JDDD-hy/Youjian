import { Link } from 'react-router-dom';

type PlaceholderPageProps = {
  title: string;
};

export function PlaceholderPage({ title }: PlaceholderPageProps) {
  return (
    <main className="page-shell">
      <section className="placeholder-card">
        <p className="eyebrow">友间</p>
        <h1>{title}</h1>
        <p>这个地址不存在，返回友间首页即可继续。</p>
        <Link className="text-link" to="/">
          返回欢迎页
        </Link>
      </section>
    </main>
  );
}
