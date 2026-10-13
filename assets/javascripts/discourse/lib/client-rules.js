// Deterministic UI helpers. Server rules remain authoritative.
const DAY_MS = 86_400_000;
function parseDate(value) {
  if (typeof value !== "string" || !/^\d{4}-\d{2}-\d{2}$/.test(value)) { return null; }
  const date = new Date(`${value}T00:00:00Z`);
  return !Number.isNaN(date.getTime()) && date.toISOString().slice(0, 10) === value ? date : null;
}
export function defaultEndDate(start, count) {
  const date = parseDate(start);
  if (!date || !Number.isInteger(count) || count < 1 || count > 366) { return ""; }
  return new Date(date.getTime() + (count - 1) * DAY_MS).toISOString().slice(0, 10);
}
export function calendarDays(start, end, completed, today) {
  const first = parseDate(start), last = parseDate(end);
  if (!first || !last || !parseDate(today)) { return []; }
  const length = Math.round((last - first) / DAY_MS) + 1;
  if (length < 1 || length > 366) { return []; }
  const checked = new Set(completed);
  return Array.from({ length }, (_, index) => {
    const date = new Date(first.getTime() + index * DAY_MS).toISOString().slice(0, 10);
    return { date, label: date.slice(5), state: checked.has(date) ? "complete" : date > today ? "future" : "open" };
  });
}
export function goalLink(id) {
  if (!Number.isSafeInteger(id) || id <= 0) { throw new Error("Invalid goal identifier"); }
  return `/learning?goal_id=${id}`;
}
export function profileLink(username) {
  return `/learning?username=${encodeURIComponent(username)}`;
}
export function requestToken() { return globalThis.crypto.randomUUID(); }
export function errorText(error, fallback) {
  const errors = error?.jqXHR?.responseJSON?.errors || error?.responseJSON?.errors;
  return Array.isArray(errors) && errors.length ? errors.map(String).join("；") : fallback;
}
