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
      const rawBefore = query.get('before')
      // `before` is the server time of the oldest message the client already
      // has; omitting it returns the newest page.
      const before = rawBefore == null ? null : Number(rawBefore)
      if (rawBefore != null && !Number.isFinite(before)) {
        throw badRequest('bad_cursor', 'before must be a millisecond timestamp')
      }

      const messages = store.history(channel, { limit, before })
      return sendJson(res, 200, {
        channel,
        messages,
        // Short page means we reached the beginning — the client stops asking.
        hasMore: messages.length === limit,
      })
    },
  }
}
