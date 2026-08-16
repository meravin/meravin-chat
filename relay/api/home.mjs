// One call that fills the whole Home tab: greeting, weather, whisper, "Day N",
// the anniversary countdowns, and the latest health snapshot.
import { sendJson, readJson } from './http.mjs'
import { dayCount, greeting, headerDate, nextAnnual, nextMonthly, todayISO } from './dates.mjs'

export function homeRoutes({ store, weather, whisper, names }) {
  return {
    'GET /api/home': async (req, res) => {
      const now = new Date()
      const today = todayISO(now)
      const profile = store.getProfile()
      const health = store.latestHealth()

      const since = profile.togetherSince || null
      const userName = profile.userName || names.user || ''
      const partner = profile.aiAName || names.ai_a || ''

      // Both are best-effort: a missing key or a cold network must not stop the
      // rest of the screen from rendering.
      const [weatherNow, whisperToday] = await Promise.all([
        weather.current().catch(() => null),
        whisper.forDate(today).catch(() => null),
      ])

      const anniversaries = []
      if (profile.birthday) {
        const next = nextAnnual(profile.birthday, today)
        if (next) anniversaries.push({ key: 'birthday', label: `${userName}'s birthday`, ...next })
      }
      if (profile.anniversary) {
        const next = nextAnnual(profile.anniversary, today)
        if (next) anniversaries.push({ key: 'anniversary', label: 'anniversary', ...next })
      }

      return sendJson(res, 200, {
        date: today,
        headerDate: headerDate(now),
        greeting: greeting(now),
        userName,
        weather: weatherNow,
        whisper: whisperToday,
        us: since
          ? { day: dayCount(since, today), since, partner, userName }
          : null,
        monthly: since ? nextMonthly(since, today) : null,
        anniversaries,
        health: health?.payload ?? null,
        syncedAt: health?.syncedAt ?? null,
      })
    },

    'GET /api/profile': async (req, res) => sendJson(res, 200, { profile: store.getProfile() }),

    // Settings writes names and dates here, so nothing personal is hardcoded.
    'PATCH /api/profile': async (req, res) => {
      const body = await readJson(req)
      const allowed = [
        'userName', 'aiAName', 'aiBName', 'groupName',
        'togetherSince', 'birthday', 'anniversary',
        'signature', 'epigraph',
      ]
      const patch = {}
      for (const key of allowed) if (key in body) patch[key] = body[key]
      return sendJson(res, 200, { profile: store.setProfile(patch) })
    },
  }
}
