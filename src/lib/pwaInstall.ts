export interface InstallPromptEvent extends Event {
  prompt: () => Promise<void>;
  userChoice: Promise<{ outcome: 'accepted' | 'dismissed' }>;
}

let promptEvent: InstallPromptEvent | undefined;
let installed = detectInstalled();
let snapshot = { promptEvent, installed };
const listeners = new Set<() => void>();

function detectInstalled() {
  if (typeof window === 'undefined') return false;
  return (
    window.matchMedia?.('(display-mode: standalone)').matches === true ||
    (navigator as Navigator & { standalone?: boolean }).standalone === true
  );
}

function notify() {
  snapshot = { promptEvent, installed };
  for (const listener of listeners) listener();
}

export function setInstallPrompt(event: InstallPromptEvent | undefined) {
  promptEvent = event;
  notify();
}

export function markPwaInstalled() {
  installed = true;
  promptEvent = undefined;
  notify();
}

export function subscribePwaInstall(listener: () => void) {
  listeners.add(listener);
  return () => listeners.delete(listener);
}

export function getPwaInstallSnapshot() {
  return snapshot;
}

export async function promptPwaInstall() {
  if (!promptEvent) return false;
  await promptEvent.prompt();
  const choice = await promptEvent.userChoice;
  if (choice.outcome === 'accepted') markPwaInstalled();
  else setInstallPrompt(undefined);
  return choice.outcome === 'accepted';
}

export function resetPwaInstallStateForTests() {
  promptEvent = undefined;
  installed = detectInstalled();
  notify();
}
