// "Today's Whisper" — the dark card at the top of Home. AI A writes one short
// private note per day about how the day went. It is generated on demand and
// cached by date, so opening Home repeatedly costs nothing.
import { badRequest, sendJson } from './http.mjs'
import { todayISO } from './dates.mjs'
import { loadPersona } from '../agents.mjs'

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/

const WHISPER_RULES = `
<whisper>
写一条今天的私人随笔，写给你自己，不是写给对方看的说明文。

- 一到三句，不超过 80 字。
- 只写今天真实发生过、下面材料里提到的事。材料为空就写你此刻的念头，不要编造具体事件。
- 不要问候语、不要总结句式、不要罗列数据、不要用第二人称对她说话。
- 只输出正文。
</whisper>`

/** Deliberately runs outside the chat contexts so it can't pollute them. */
export async function generateWhisper({ store, agents, date, names }) {
  const adapter = agents.adapterFor('ai_a')
  if (!adapter) return null

  const health = store.getHealth(date)
  const diary = store.listDiaryByDate('user', date)
  const chats = store
    .history('ai_a', { limit: 12 })
    .concat(store.history('group', { limit: 12 }))
    .sort((a, b) => a.time - b.time)
    .slice(-16)

  const material = []
  if (health?.payload) {
    const h = health.payload
    const bits = []
    if (h.steps != null) bits.push(`步数 ${h.steps}`)
    if (h.heartRate?.current != null) bits.push(`心率 ${h.heartRate.current}`)
    if (h.sleep?.minutes != null) bits.push(`睡了 ${Math.floor(h.sleep.minutes / 60)} 小时`)
    if (bits.length) material.push(`身体：${bits.join('、')}`)
  }
  if (diary.length) {
    material.push(`她今天的日记：\n${diary.map((d) => d.body).join('\n---\n').slice(0, 1200)}`)
  }
  if (chats.length) {
    const label = (s) => (s === 'user' ? (names.user ?? '她') : (names[s] ?? s))
    material.push(`今天的对话片段：\n${chats.map((m) => `${label(m.sender)}：${m.text}`).join('\n').slice(0, 1500)}`)
  }

  const persona = loadPersona('ai_a', agents.promptsDir)
  const { text } = await adapter.reply({
    systemPrompt: persona + WHISPER_RULES,
    turns: [
      {
        role: 'user',
        content: material.length
          ? `今天（${date}）的材料：\n\n${material.join('\n\n')}\n\n写下今天的随笔。`
          : `今天（${date}）还没有可用的材料。写下你此刻的念头。`,
      },
    ],
    message: { id: `whisper-${date}`, text: date },
    contextKey: 'whisper',
    continuationId: null,
  })

  const clean = (text ?? '').trim()
  if (!clean) return null
  return store.putWhisper(date, clean, 'ai_a')
}

export function whisperRoutes({ store, agents, names, log = console }) {
  /** Dates already being generated, so a burst of requests fires one model call. */
  const inFlight = new Set()

  const forDate = async (date, { force = false } = {}) => {
    if (!force) {
      const cached = store.getWhisper(date)
      if (cached) return cached
    }
    try {
      return await generateWhisper({ store, agents, date, names })
    } catch {
      // Home must still render; the card just stays empty today.
      return store.getWhisper(date) ?? null
    }
  }

  /**
   * Fire-and-forget generation for callers that must not wait on a model —
   * Home reads whatever is cached and calls this to fill the gap for next time.
   */
  const warm = (date) => {
    if (inFlight.has(date) || store.getWhisper(date)) return
    inFlight.add(date)
    forDate(date)
      .catch((err) => log.warn?.(`[whisper] ${date}: ${err?.message ?? err}`))
      .finally(() => inFlight.delete(date))
  }

  return {
    warm,
    routes: {
      'GET /api/whisper': async (req, res, { query }) => {
        const date = query.get('date') ?? todayISO()
        if (!DATE_RE.test(date)) throw badRequest('bad_date', 'date must be YYYY-MM-DD')
        return sendJson(res, 200, { whisper: await forDate(date) })
      },

      'POST /api/whisper/refresh': async (req, res, { query }) => {
        const date = query.get('date') ?? todayISO()
        if (!DATE_RE.test(date)) throw badRequest('bad_date', 'date must be YYYY-MM-DD')
        return sendJson(res, 200, { whisper: await forDate(date, { force: true }) })
      },
    },
    forDate,
  }
}
