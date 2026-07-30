import { Component, type ErrorInfo, type ReactNode } from 'react';
import { reportSafeError } from '../lib/safeError';
import { appBasePath } from '../lib/appBase';

export class AppErrorBoundary extends Component<
  { children: ReactNode },
  { failed: boolean }
> {
  state = { failed: false };

  static getDerivedStateFromError() {
    return { failed: true };
  }

  private readonly onWindowError = (event: ErrorEvent) =>
    reportSafeError(event.error, 'window_error');
  private readonly onUnhandledRejection = (event: PromiseRejectionEvent) =>
    reportSafeError(event.reason, 'unhandled_rejection');

  componentDidMount() {
    window.addEventListener('error', this.onWindowError);
    window.addEventListener('unhandledrejection', this.onUnhandledRejection);
  }

  componentWillUnmount() {
    window.removeEventListener('error', this.onWindowError);
    window.removeEventListener('unhandledrejection', this.onUnhandledRejection);
  }

  componentDidCatch(error: Error, _info: ErrorInfo) {
    void _info;
    reportSafeError(error, 'react_error_boundary');
  }

  render() {
    if (this.state.failed) {
      return (
        <main className="fatal-page" role="alert">
          <section className="state-card">
            <h1>页面暂时无法使用</h1>
            <p>你的输入内容没有被记录。请重新打开应用后再试。</p>
            <button
              className="button button--primary"
              onClick={() => window.location.assign(appBasePath)}
            >
              返回欢迎页
            </button>
          </section>
        </main>
      );
    }
    return this.props.children;
  }
}
