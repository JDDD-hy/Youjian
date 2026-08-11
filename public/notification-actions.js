self.addEventListener('notificationclick', (event) => {
  const data = event.notification && event.notification.data;
  if (!data || data.kind !== 'focus-health-check') return;
  event.notification.close();
  event.waitUntil(
    (async () => {
      const action =
        event.action === 'end' || event.action === 'continue'
          ? event.action
          : null;
      const windows = await self.clients.matchAll({
        type: 'window',
        includeUncontrolled: true,
      });
    const target = windows[0];
    if (target) {
      if (action) {
        target.postMessage({
          type: 'focus-health-action',
          action,
          sessionId: data.sessionId,
        });
        return;
      }
      await target.focus();
      return;
      }
      const url = new URL(data.url || self.registration.scope);
      if (action) {
        url.searchParams.set('focusHealthAction', action);
        url.searchParams.set('focusHealthSession', data.sessionId);
      }
      await self.clients.openWindow(url.href);
    })(),
  );
});
