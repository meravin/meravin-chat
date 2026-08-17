// Native apps authenticate with `Authorization: Bearer <token>`. Browsers can't
// set headers on `new WebSocket()`, so they POST /api/ws-ticket first and pass
// the short-lived, single-use ticket as a query param instead.
import { randomBytes, timingSafeEqual } from 'node:crypto'

const TICKET_TTL_MS = 30_000

const constantTimeEquals = (a, b) => {
  const ba = Buffer.from(String(a ?? ''), 'utf8')
  const bb = Buffer.from(String(b ?? ''), 'utf8')
  // timingSafeEqual throws on length mismatch, so compare a fixed-size digest of
  // the lengths first and always run the comparison to keep timing flat.
  if (ba.length !== bb.length) {
    timingSafeEqual(ba, ba)
    return false
  }
  return timingSafeEqual(ba, bb)
}

export function createAuth({ token, allowedOrigins = [] }) {
  if (!token || String(token).length < 16) {
    throw new Error('YOURCHAT_TOKEN must be set to a random string of at least 16 characters')
  }

  const origins = new Set(allowedOrigins.filter(Boolean))
  const tickets = new Map() // ticket -> expiresAt

  const sweep = (now = Date.now()) => {
    for (const [t, expires] of tickets) if (expires <= now) tickets.delete(t)
  }

  return {
    /**
     * Browser Origin check. Native clients send no Origin at all and pass on
     * the bearer token alone; a present Origin must be on the allowlist. Never
     * "allow all origins" — that is what lets any web page open a socket.
     */
    originAllowed(origin) {
      if (!origin) return true
      return origins.has(origin)
    },

    bearerFromHeaders(headers) {
      const raw = headers?.authorization ?? headers?.Authorization
      if (typeof raw !== 'string') return null
      const [scheme, value] = raw.split(' ')
      return scheme?.toLowerCase() === 'bearer' && value ? value : null
    },

    tokenValid: (candidate) => constantTimeEquals(candidate, token),

    issueTicket(now = Date.now()) {
      sweep(now)
      const ticket = randomBytes(24).toString('base64url')
      tickets.set(ticket, now + TICKET_TTL_MS)
      return { ticket, expiresIn: TICKET_TTL_MS / 1000 }
    },

    /** Single use: a redeemed ticket is destroyed even if it was still valid. */
    redeemTicket(ticket, now = Date.now()) {
      sweep(now)
      if (!ticket || !tickets.has(ticket)) return false
      tickets.delete(ticket)
      return true
    },

    /** Returns { ok, reason }. Used for both the HTTP API and the WS upgrade. */
    check({ headers = {}, origin = null, ticket = null } = {}) {
      if (!this.originAllowed(origin)) return { ok: false, reason: 'origin_not_allowed' }
      const bearer = this.bearerFromHeaders(headers)
      if (bearer) {
        return this.tokenValid(bearer) ? { ok: true } : { ok: false, reason: 'bad_token' }
      }
      if (ticket) {
        return this.redeemTicket(ticket) ? { ok: true } : { ok: false, reason: 'bad_ticket' }
      }
      return { ok: false, reason: 'no_credentials' }
    },
  }
}
