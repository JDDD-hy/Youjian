export function parseHistoryPage(value: string, max: number) {
  const raw = value.trim();
  const page = Number(raw);
  return /^[0-9]+$/.test(raw) &&
    Number.isSafeInteger(page) &&
    page >= 1 &&
    page <= max
    ? page
    : null;
}
