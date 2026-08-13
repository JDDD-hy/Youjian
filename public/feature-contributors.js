(() => {
  const currentUrl = new URL(window.location.href);
  const fallbackHome =
    currentUrl.protocol === 'file:'
      ? new URL('../index.html', currentUrl.href).href
      : new URL('./', currentUrl.href).href;

  const cameFromSameSite = (() => {
    if (!document.referrer) return false;
    try {
      return new URL(document.referrer).origin === window.location.origin;
    } catch {
      return false;
    }
  })();

  document.querySelectorAll('[data-app-home]').forEach((link) => {
    link.setAttribute('href', fallbackHome);
  });

  document.querySelectorAll('[data-history-back]').forEach((link) => {
    link.setAttribute('href', fallbackHome);
    if (!cameFromSameSite || window.history.length <= 1) return;
    link.addEventListener('click', (event) => {
      event.preventDefault();
      window.history.back();
    });
  });
})();
