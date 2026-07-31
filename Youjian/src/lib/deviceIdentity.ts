import type { QueryClient } from '@tanstack/react-query';
import { getSupabaseClient } from './supabase';

export async function clearDeviceIdentity(queryClient?: QueryClient) {
  try {
    await getSupabaseClient().auth.signOut({ scope: 'local' });
  } catch {
    // A transferred/revoked identity may no longer be accepted by Auth. Local
    // cleanup must still continue so the device can create a fresh identity.
  }

  for (let index = localStorage.length - 1; index >= 0; index -= 1) {
    const key = localStorage.key(index);
    if (key?.startsWith('youjian:')) localStorage.removeItem(key);
  }
  sessionStorage.clear();
  queryClient?.clear();
}
