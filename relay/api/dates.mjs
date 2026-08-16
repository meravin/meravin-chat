// Date math for the Home screen. Verified against the reference screen recording:
// with togetherSince = 2026-06-22 and today = 2026-07-26 these produce
// Day 35, birthday Jan 6 -> 164, anniversary Jun 22 -> 331, monthly -> 27.

/** Local calendar date as YYYY-MM-DD (not UTC — "today" must match the phone). */
export function todayISO(now = new Date()) {
  const y = now.getFullYear()
  const m = String(now.getMonth() + 1).padStart(2, '0')
  const d = String(now.getDate()).padStart(2, '0')
  return `${y}-${m}-${d}`
}

/** Midnight UTC for a YYYY-MM-DD, so day counts never drift across DST. */
const utcDay = (iso) => {
  const [y, m, d] = iso.split('-').map(Number)
  return Date.UTC(y, m - 1, d)
}

export const daysBetween = (fromISO, toISO) =>
  Math.round((utcDay(toISO) - utcDay(fromISO)) / 86_400_000)

/** "Day N" counts the first day as day 1. */
export function dayCount(sinceISO, todayIso = todayISO()) {
  if (!sinceISO) return null
  const n = daysBetween(sinceISO, todayIso)
  return n < 0 ? null : n + 1
}

/**
 * Next occurrence of a recurring MM-DD, as { date, daysUntil }.
 * Accepts either `MM-DD` or a full `YYYY-MM-DD` (the year is ignored).
 * Feb 29 falls back to Mar 1 in common years.
 */
export function nextAnnual(monthDay, todayIso = todayISO()) {
  if (!monthDay) return null
  const parts = monthDay.split('-').map(Number)
  const [month, day] = parts.length === 3 ? [parts[1], parts[2]] : [parts[0], parts[1]]
  if (!month || !day) return null

  const [ty] = todayIso.split('-').map(Number)
  for (const year of [ty, ty + 1]) {
    const dt = new Date(Date.UTC(year, month - 1, day))
    // Rolled over (e.g. Feb 29 in a common year) — clamp to the next real day.
    const iso = dt.toISOString().slice(0, 10)
    const daysUntil = daysBetween(todayIso, iso)
    if (daysUntil >= 0) return { date: iso, daysUntil }
  }
  return null
}

/**
 * Next monthly anniversary: the same day-of-month as `sinceISO`.
 * Months without that day (e.g. the 31st in April) clamp to the last day.
 */
export function nextMonthly(sinceISO, todayIso = todayISO()) {
  if (!sinceISO) return null
  const targetDay = Number(sinceISO.split('-')[2])
  const [ty, tm] = todayIso.split('-').map(Number)

  for (let offset = 0; offset <= 1; offset += 1) {
    const year = ty + Math.floor((tm - 1 + offset) / 12)
    const month = ((tm - 1 + offset) % 12) + 1
    const lastDay = new Date(Date.UTC(year, month, 0)).getUTCDate()
    const day = Math.min(targetDay, lastDay)
    const iso = `${year}-${String(month).padStart(2, '0')}-${String(day).padStart(2, '0')}`
    const daysUntil = daysBetween(todayIso, iso)
    if (daysUntil > 0) return { date: iso, daysUntil }
  }
  return null
}

/** Matches the reference app: "Good evening" is still correct at 23:57. */
export function greeting(now = new Date()) {
  const h = now.getHours()
  if (h < 5) return 'Good night'
  if (h < 12) return 'Good morning'
  if (h < 18) return 'Good afternoon'
  return 'Good evening'
}

const WEEKDAYS = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday']
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June',
  'July', 'August', 'September', 'October', 'November', 'December']

/** "Sunday, July 26" — the Home header line. */
export function headerDate(now = new Date()) {
  return `${WEEKDAYS[now.getDay()]}, ${MONTHS[now.getMonth()]} ${now.getDate()}`
}
