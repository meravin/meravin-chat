// A pocket-sized router. The relay serves one origin with a handful of routes;
// a framework would be more machinery than the whole surface it manages.
const MAX_BODY_BYTES = 2 * 1024 * 1024

export class HttpError extends Error {
  constructor(status, code, message) {
    super(message ?? code)
    this.name = 'HttpError'
    this.status = status
    this.code = code
  }
}

export const badRequest = (code, message) => new HttpError(400, code, message)
export const notFound = (message = 'not found') => new HttpError(404, 'not_found', message)

export function sendJson(res, status, body) {
  const payload = JSON.stringify(body)
  res.writeHead(status, {
    'content-type': 'application/json; charset=utf-8',
    'content-length': Buffer.byteLength(payload),
    'cache-control': 'no-store',
  })
  res.end(payload)
}

export async function readJson(req) {
  const chunks = []
  let size = 0
  for await (const chunk of req) {
    size += chunk.length
    if (size > MAX_BODY_BYTES) throw new HttpError(413, 'body_too_large', 'request body too large')
    chunks.push(chunk)
  }
  if (!chunks.length) return {}
  try {
    return JSON.parse(Buffer.concat(chunks).toString('utf8'))
  } catch {
    throw badRequest('bad_json', 'body is not valid JSON')
  }
}

/**
 * Routes are declared as `METHOD /api/thing/:id`. Returns a `handle` that
 * resolves a request to { handler, params } or null.
 */
export function createRouter(routes) {
  const compiled = Object.entries(routes).map(([spec, handler]) => {
    const [method, path] = spec.split(' ')
    const names = []
    const pattern = path
      .split('/')
      .map((seg) => {
        if (!seg.startsWith(':')) return seg.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
        names.push(seg.slice(1))
        return '([^/]+)'
      })
      .join('/')
    return { method, re: new RegExp(`^${pattern}$`), names, handler }
  })

  return function match(method, pathname) {
    for (const route of compiled) {
      if (route.method !== method) continue
      const m = route.re.exec(pathname)
      if (!m) continue
      const params = {}
      route.names.forEach((name, i) => {
        params[name] = decodeURIComponent(m[i + 1])
      })
      return { handler: route.handler, params }
    }
    return null
  }
}
