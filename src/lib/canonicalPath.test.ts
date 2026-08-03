import { describe, expect, it } from 'vitest';
import { canonicalAppPath } from './canonicalPath';

describe('canonicalAppPath', () => {
  it('repairs a legacy lowercase project path', () => {
    expect(canonicalAppPath('/youjian/invite/token', '/Youjian/')).toBe(
      '/Youjian/invite/token',
    );
  });

  it('removes duplicated project paths while preserving the route', () => {
    expect(canonicalAppPath('/youjian/Youjian/invite/token', '/Youjian/')).toBe(
      '/Youjian/invite/token',
    );
    expect(
      canonicalAppPath('/old/Youjian/space/id/settings', '/Youjian/'),
    ).toBe('/Youjian/space/id/settings');
  });

  it('leaves canonical and unrelated paths unchanged', () => {
    expect(canonicalAppPath('/Youjian/invite/token', '/Youjian/')).toBeNull();
    expect(canonicalAppPath('/unrelated/invite/token', '/Youjian/')).toBeNull();
  });
});
