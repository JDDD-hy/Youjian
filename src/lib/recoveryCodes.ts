import { rpc } from './api';

export interface RecoveryCodeSet {
  codes: string[];
  generated_at: string;
  generation_id: string;
}

export async function rotateRecoveryCodes() {
  return rpc<RecoveryCodeSet>('rotate_identity_recovery_codes');
}

export function recoveryCodesText(
  codes: string[],
  displayName: string,
  generatedAt: string,
) {
  return [
    '友间身份恢复码',
    `身份昵称：${displayName}`,
    `生成时间：${generatedAt}`,
    '',
    ...codes.map((code, index) => `${index + 1}. ${code}`),
    '',
    '每个恢复码只能使用一次。请保存在密码管理器、个人云盘或离线介质中。',
    '不要将恢复码发送给任何人；重新生成后，旧恢复码全部失效。',
  ].join('\n');
}

export function downloadRecoveryCodes(
  codes: string[],
  displayName: string,
  generatedAt: string,
) {
  const blob = new Blob([recoveryCodesText(codes, displayName, generatedAt)], {
    type: 'text/plain;charset=utf-8',
  });
  const url = URL.createObjectURL(blob);
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = 'youjian-recovery-codes.txt';
  document.body.appendChild(anchor);
  anchor.click();
  anchor.remove();
  window.setTimeout(() => URL.revokeObjectURL(url), 1_000);
}
