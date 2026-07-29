import { describe, expect, it, vi } from 'vitest';
import {
  getPwaInstallSnapshot,
  promptPwaInstall,
  resetPwaInstallStateForTests,
  setInstallPrompt,
} from './pwaInstall';

describe('pwaInstall', () => {
  it('shares an accepted install prompt with settings consumers', async () => {
    resetPwaInstallStateForTests();
    const prompt = vi.fn(() => Promise.resolve());
    setInstallPrompt(
      Object.assign(new Event('beforeinstallprompt'), {
        prompt,
        userChoice: Promise.resolve({ outcome: 'accepted' as const }),
      }),
    );
    expect(getPwaInstallSnapshot().promptEvent).toBeDefined();
    await expect(promptPwaInstall()).resolves.toBe(true);
    expect(prompt).toHaveBeenCalledOnce();
    expect(getPwaInstallSnapshot()).toMatchObject({
      installed: true,
      promptEvent: undefined,
    });
  });
});
