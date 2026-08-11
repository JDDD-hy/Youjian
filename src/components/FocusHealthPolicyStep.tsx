export function FocusHealthPolicyStep({
  pending,
  error,
  onConfirm,
  onBack,
}: {
  pending: boolean;
  error?: string;
  onConfirm: () => void;
  onBack: () => void;
}) {
  return (
    <div className="focus-health-policy">
      <img src={appPath('lamp-dimmed.svg')} alt="" width="132" height="120" />
      <h2 id="start-title">让灯光也记得休息</h2>
      <p>每次累计专注两小时后，友间会邀请你稍作休息。</p>
      <p>
        你可以结束本次专注，也可以继续至六小时；若 1
        分钟内没有选择，本次专注将自动结束。
      </p>
      <p>
        最近 30 分钟有效专注内，若已暂停满 5 分钟，将视为已经休息，不再询问。
      </p>
      <p>即使关闭桌面通知，这项健康检查规则仍会生效。</p>
      {error && (
        <p className="field-error" role="alert">
          {error}
        </p>
      )}
      <button
        data-autofocus
        className="button button--primary button--full"
        type="button"
        disabled={pending}
        onClick={onConfirm}
      >
        {pending ? '正在保存…' : '知道了，点亮台灯'}
      </button>
      <button
        className="button button--text button--full"
        type="button"
        disabled={pending}
        onClick={onBack}
      >
        返回
      </button>
    </div>
  );
}
import { appPath } from '../lib/appBase';
