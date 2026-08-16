import { createRouter } from './http.mjs'
import { homeRoutes } from './home.mjs'
import { diaryRoutes } from './diary.mjs'
import { todoRoutes } from './todos.mjs'
import { healthRoutes } from './health.mjs'
import { whisperRoutes } from './whisper.mjs'
import { messageRoutes } from './messages.mjs'
import { searchRoutes } from './search.mjs'
import { dataRoutes } from './data.mjs'

/**
 * Chat runs on the WebSocket because it has to be pushed. Everything else —
 * older pages, diary, todos, health, search, export — is request/response, so
 * it is plain HTTP on the same port behind the same bearer check.
 */
export function createApi({ store, agents, weather, auth, names, backups }) {
  const whisper = whisperRoutes({ store, agents, names })

  const routes = {
    // Browser clients can't set an Authorization header on `new WebSocket()`,
    // so they trade the bearer token for a short-lived, single-use ticket here.
    'POST /api/ws-ticket': async (req, res) => {
      const { ticket, expiresIn } = auth.issueTicket()
      res.writeHead(200, { 'content-type': 'application/json', 'cache-control': 'no-store' })
      res.end(JSON.stringify({ ticket, expiresIn }))
    },
    ...homeRoutes({ store, weather, whisper, names }),
    ...messageRoutes({ store }),
    ...diaryRoutes({ store, agents }),
    ...todoRoutes({ store }),
    ...healthRoutes({ store }),
    ...searchRoutes({ store }),
    ...dataRoutes({ store, backups }),
    ...whisper.routes,
  }

  return { match: createRouter(routes), whisper }
}
