// The iOS app reads HealthKit and posts a snapshot here. That upload is what
// the "sync · 11:57 PM" stamp on the Home header reports, and it is how the two
// AIs get to know how her day actually went.
import { badRequest, readJson, sendJson } from './http.mjs'
import { todayISO } from './dates.mjs'

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

/**
 * Keeps only the fields the Home cards and the prompts actually use, so a
 * future HealthKit addition can't silently balloon what we store or send to a
 * model. Unknown keys are dropped rather than passed through.
 */
function sanitize(raw) {
  const out = {}
  const num = (v) => (typeof v === 'number' && Number.isFinite(v) ? v : undefined)

  if (num(raw.steps) !== undefined) out.steps = Math.round(raw.steps)
  if (num(raw.distanceKm) !== undefined) out.distanceKm = Number(raw.distanceKm.toFixed(2))
  if (Array.isArray(raw.stepsByWeekday)) {
    out.stepsByWeekday = raw.stepsByWeekday.slice(0, 7).map((v) => num(v) ?? 0)
  }

  if (raw.heartRate && typeof raw.heartRate === 'object') {
    const hr = {}
    if (num(raw.heartRate.current) !== undefined) hr.current = Math.round(raw.heartRate.current)
    if (num(raw.heartRate.min) !== undefined) hr.min = Math.round(raw.heartRate.min)
    if (num(raw.heartRate.max) !== undefined) hr.max = Math.round(raw.heartRate.max)
    if (Array.isArray(raw.heartRate.series)) {
      hr.series = raw.heartRate.series.slice(0, 240).map((v) => num(v) ?? 0)
    }
    if (Object.keys(hr).length) out.heartRate = hr
  }

  if (raw.sleep && typeof raw.sleep === 'object') {
    const s = {}
    if (num(raw.sleep.minutes) !== undefined) s.minutes = Math.round(raw.sleep.minutes)
    if (typeof raw.sleep.start === 'string') s.start = raw.sleep.start
    if (typeof raw.sleep.end === 'string') s.end = raw.sleep.end
    if (Array.isArray(raw.sleep.stages)) {
      s.stages = raw.sleep.stages.slice(0, 64).map((st) => ({
        stage: String(st?.stage ?? 'unknown'),
        minutes: num(st?.minutes) ?? 0,
      }))
    }
    if (Object.keys(s).length) out.sleep = s
  }

  if (raw.cycle && typeof raw.cycle === 'object') {
    const c = {}
    if (num(raw.cycle.day) !== undefined) c.day = Math.round(raw.cycle.day)
    if (num(raw.cycle.length) !== undefined) c.length = Math.round(raw.cycle.length)
    if (typeof raw.cycle.nextExpected === 'string') c.nextExpected = raw.cycle.nextExpected
    if (Object.keys(c).length) out.cycle = c
  }

  if (raw.body && typeof raw.body === 'object') {
    const b = {}
    if (num(raw.body.oxygen) !== undefined) b.oxygen = raw.body.oxygen
    if (num(raw.body.hrv) !== undefined) b.hrv = raw.body.hrv
    if (num(raw.body.temperature) !== undefined) b.temperature = raw.body.temperature
    if (num(raw.body.weightKg) !== undefined) b.weightKg = raw.body.weightKg
    if (Object.keys(b).length) out.body = b
  }

  return out
}

export function healthRoutes({ store }) {
  return {
    'GET /api/health': async (req, res, { query }) => {
      const date = query.get('date')
      if (date && !DATE_RE.test(date)) throw badRequest('bad_date', 'date must be YYYY-MM-DD')
      const snapshot = date ? store.getHealth(date) : store.latestHealth()
      return sendJson(res, 200, { snapshot: snapshot ?? null })
    },

    'POST /api/health': async (req, res) => {
      const body = await readJson(req)
      const date = body.date ?? todayISO()
      if (!DATE_RE.test(date)) throw badRequest('bad_date', 'date must be YYYY-MM-DD')
      const payload = body.payload ?? body
      if (!payload || typeof payload !== 'object') throw badRequest('bad_payload', 'payload must be an object')

      const snapshot = store.putHealth(date, sanitize(payload))
      return sendJson(res, 200, { snapshot })
    },
  }
}

export const sanitizeHealth = sanitize
