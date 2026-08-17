// Two diaries side by side — the user's and the AI's — which is what the
// segmented control at the top of the Diary tab switches between.
import { randomUUID } from 'node:crypto'
import { badRequest, notFound, readJson, sendJson } from './http.mjs'
import { todayISO } from './dates.mjs'
import { loadPersona } from '../agents.mjs'

const AUTHORS = new Set(['user', 'ai_a', 'ai_b'])
const DATE_RE = /^\d{4}-\d{2}-\d{2}$/
const MONTH_RE = /^\d{4}-\d{2}$/

const requireAuthor = (value) => {
  const author = value ?? 'user'
  if (!AUTHORS.has(author)) throw badRequest('bad_author', `unknown author: ${author}`)
  return author
}

const EXTRACT_RULES = `
<extract_todos>
你在读一篇日记，任务是找出里面**还没做完、之后要做**的具体事情。

- 每行一条，不要编号、不要符号前缀、不要任何解释。
- 只写具体到能动手的事。情绪、感想、已经做完的事都不要。
- 最多 5 条。一条都没有就输出空内容，不要写「没有」。
- 用日记原话的说法，不要改写成书面语。
</extract_todos>`

/** Reads one entry and proposes todos. Returns candidates only — never writes. */
async function extractTodos({ store, agents, entry }) {
  const adapter = agents?.adapterFor('ai_a')
  if (!adapter) return []

  const { text } = await adapter.reply({
    systemPrompt: loadPersona('ai_a', agents.promptsDir) + EXTRACT_RULES,
    turns: [{ role: 'user', content: `日记（${entry.date}）：\n\n${entry.body}` }],
    message: { id: `extract-${entry.id}`, text: entry.body },
    contextKey: 'extract',
    continuationId: null,
  })

  return (text ?? '')
    .split('\n')
    .map((line) => line.replace(/^\s*(?:[-*·•]|\d+[.、)])\s*/, '').trim())
    .filter((line) => line.length > 0 && line.length <= 120)
    .slice(0, 5)
}

/** "7月25日记的" — the source label the reference app shows under a todo. */
function sourceLabel(date) {
  const [, month, day] = date.split('-').map(Number)
  return `${month}月${day}日记的`
}

export function diaryRoutes({ store, agents = null }) {
  return {
    // Proposes todos from an entry. The app shows them for confirmation; this
    // endpoint deliberately creates nothing on its own.
    'POST /api/diary/:id/todos': async (req, res, { params }) => {
      const entry = store.getDiary(params.id)
      if (!entry) throw notFound('no such diary entry')
      try {
        const candidates = await extractTodos({ store, agents, entry })
        return sendJson(res, 200, { candidates, source: sourceLabel(entry.date) })
      } catch {
        // A model hiccup shouldn't look like a broken diary.
        return sendJson(res, 200, { candidates: [], source: sourceLabel(entry.date) })
      }
    },

    'GET /api/diary': async (req, res, { query }) => {
      const author = requireAuthor(query.get('author'))
      const date = query.get('date')
      if (date) {
        if (!DATE_RE.test(date)) throw badRequest('bad_date', 'date must be YYYY-MM-DD')
        return sendJson(res, 200, { author, date, entries: store.listDiaryByDate(author, date) })
      }
      const limit = Math.min(Number(query.get('limit')) || 60, 300)
      return sendJson(res, 200, { author, entries: store.listDiary(author, limit) })
    },

    // Feeds the dots under the days in the month calendar.
    'GET /api/diary/marks': async (req, res, { query }) => {
      const author = requireAuthor(query.get('author'))
      const month = query.get('month') ?? todayISO().slice(0, 7)
      if (!MONTH_RE.test(month)) throw badRequest('bad_month', 'month must be YYYY-MM')
      return sendJson(res, 200, { author, month, marks: store.diaryMarks(author, month) })
    },

    'POST /api/diary': async (req, res) => {
      const body = await readJson(req)
      const author = requireAuthor(body.author)
      const date = body.date ?? todayISO()
      if (!DATE_RE.test(date)) throw badRequest('bad_date', 'date must be YYYY-MM-DD')
      const text = typeof body.body === 'string' ? body.body.trim() : ''
      if (!text) throw badRequest('empty_body', 'body is required')

      const entry = store.createDiary({
        id: body.id ?? randomUUID(),
        author,
        date,
        mood: body.mood ?? null,
        body: text,
      })
      return sendJson(res, 201, { entry })
    },

    'PATCH /api/diary/:id': async (req, res, { params }) => {
      if (!store.getDiary(params.id)) throw notFound('no such diary entry')
      const body = await readJson(req)
      const entry = store.updateDiary(params.id, {
        mood: body.mood,
        body: typeof body.body === 'string' ? body.body.trim() : undefined,
      })
      return sendJson(res, 200, { entry })
    },

    'DELETE /api/diary/:id': async (req, res, { params }) => {
      if (!store.deleteDiary(params.id)) throw notFound('no such diary entry')
      return sendJson(res, 200, { deleted: params.id })
    },
  }
}
