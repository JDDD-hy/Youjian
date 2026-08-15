export function FocusHealthPolicyInfo() {
  return (
    <section className="settings-card focus-health-policy-info">
      <div className="section-heading">
        <h2>两小时健康检查</h2>
        <span>Policy v2</span>
      </div>
      <p>
        单次会话累计有效专注达到两小时后，友间会询问一次；一分钟内没有选择会由服务器自动结束。
      </p>
      <ul>
        <li>选择继续后，本次会话最长仍可专注四小时。</li>
        <li>临近两小时时暂停休息满五分钟，可视为已完成检查。</li>
        <li>桌面通知可以关闭，但健康检查规则仍会生效。</li>
      </ul>
    </section>
  );
}
