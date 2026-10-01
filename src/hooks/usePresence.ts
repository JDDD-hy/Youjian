import { createContext, useContext } from 'react';

export const PresenceContext = createContext(true);

export function usePresence() {
  return useContext(PresenceContext);
}
