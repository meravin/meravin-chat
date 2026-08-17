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

      // Weather is a short cached fetch, so it can be awaited. The whisper is a
      // model call: serve whatever is already written and generate out of band,
      // or the first Home load of the day blocks the entire screen on an AI
      // round trip. The scheduler normally has it written well before this.
      const weatherNow = await weather.current().catch(() => null)
      const whisperToday = store.getWhisper(today)
      if (!whisperToday) whisper.warm(today)

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
