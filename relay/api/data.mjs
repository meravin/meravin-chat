// Take your data out, or delete it. Both are the owner's right over their own
// archive, and the erase path is deliberately awkward to trigger by accident.
import { badRequest, readJson, sendJson } from './http.mjs'

/** Typing this exact word is the second half of the confirmation. */
const ERASE_PHRASE = 'ERASE'

export function dataRoutes({ store, backups }) {
  return {
    'GET /api/export': async (req, res) => {
      const bundle = store.exportAll()
      const stamp = bundle.exportedAt.slice(0, 10)
      const payload = JSON.stringify(bundle, null, 2)
      res.writeHead(200, {
        'content-type': 'application/json; charset=utf-8',
        'content-disposition': `attachment; filename="yourchat-${stamp}.json"`,
        'content-length': Buffer.byteLength(payload),
        'cache-control': 'no-store',
      })
      res.end(payload)
    },

    /** Manual snapshot, on top of the scheduled daily one. */
    'POST /api/backup': async (req, res) => {
      const path = await backups.runNow()
      return sendJson(res, 200, { backup: path })
    },

    'DELETE /api/data': async (req, res) => {
      const body = await readJson(req)
      if (body.confirm !== ERASE_PHRASE) {
        throw badRequest('confirmation_required',
          `send {"confirm":"${ERASE_PHRASE}"} to erase everything`)
      }

      // Snapshot first — an erase you regret is otherwise unrecoverable.
      const safety = await backups.runNow('before-erase')
      const erased = store.eraseAll()
      return sendJson(res, 200, { erased, backup: safety })
    },
  }
}
