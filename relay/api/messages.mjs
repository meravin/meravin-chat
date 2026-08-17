// Older pages of a conversation. Chat itself is pushed over the WebSocket; this
// is the pull side, so scrolling up doesn't need a second socket message type.
import { badRequest, sendJson } from './http.mjs'
import { isChannel } from '../protocol.mjs'

export function messageRoutes({ store }) {
  return {
    'GET /api/messages': async (req, res, { query }) => {
      const channel = query.get('channel')
      if (!isChannel(channel)) throw badRequest('bad_channel', `unknown channel: ${channel}`)

      const limit = Math.min(Number(query.get('limit')) || 30, 200)
      // Opaque to the client: `<ms>.<rowid>`. A bare timestamp would skip
      // messages that share a millisecond with the page boundary.
      const cursor = query.get('cursor')
      if (cursor != null && !/^\d+\.\d+$/.test(cursor)) {
        throw badRequest('bad_cursor', 'cursor must be the value returned as nextCursor')
      }

      const page = store.historyPage(channel, { limit, cursor })
      return sendJson(res, 200, {
        channel,
        messages: page.messages,
        // Null once the beginning is reached, so the client stops asking.
        nextCursor: page.hasMore ? page.cursor : null,
        hasMore: page.hasMore,
      })
    },
  }
}
