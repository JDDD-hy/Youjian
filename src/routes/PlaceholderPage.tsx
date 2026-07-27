import { Link } from 'react-router-dom';

type PlaceholderPageProps = {
  title: string;
};

export function PlaceholderPage({ title }: PlaceholderPageProps) {
  return (
    <main className="page-shell">
      <section className="placeholder-card">
        <p className="eyebrow">M0 工程基础</p>
        <h1>{title}</h1>
        <p>页面路由已就绪，业务流程将在数据库权限通过验证后接入。</p>
        <Link className="text-link" to="/">
          返回欢迎页
        </Link>
      </section>
    </main>
  );
}
