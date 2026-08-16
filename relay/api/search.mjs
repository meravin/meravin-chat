// One query across both things worth searching: what was said, and what was
// written down. Results carry enough context for the app to jump straight to
// the conversation or the diary entry.
import { badRequest, sendJson } from './http.mjs'

const MIN_QUERY = 1

export function searchRoutes({ store }) {
  return {
    'GET /api/search': async (req, res, { query }) => {
      const q = (query.get('q') ?? '').trim()
      if (q.length < MIN_QUERY) throw badRequest('empty_query', 'q is required')

      const limit = Math.min(Number(query.get('limit')) || 40, 200)
      const { messages, diary } = store.search(q, limit)

      return sendJson(res, 200, {
        query: q,
        messages: messages.map((m) => ({
          id: m.id,
          channel: m.channel,
          sender: m.sender,
          text: m.text,
          time: m.time,
        })),
        diary: diary.map((d) => ({
          id: d.id,
          author: d.author,
          date: d.date,
          mood: d.mood,
          // Enough to recognise the entry without shipping the whole thing.
          excerpt: d.body.length > 180 ? `${d.body.slice(0, 180)}…` : d.body,
        })),
      })
    },
  }
}
