// The wire contract. iOS, the relay, and the CLI client all agree on exactly
// these field names — there is no per-channel variation to remember.
export const CHANNELS = /** @type {const} */ (['ai_a', 'ai_b', 'group'])
export const SENDERS = /** @type {const} */ (['user', 'ai_a', 'ai_b'])
export const AGENTS = /** @type {const} */ (['ai_a', 'ai_b'])

// An adapter returns this when the AI decides it has nothing to add. The relay
// stores nothing and broadcasts nothing — the marker never reaches the app.
export const NO_REPLY = '__NO_REPLY__'

export const MAX_TEXT_LENGTH = 8000

const UUID_RE = /^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$/

export class ProtocolError extends Error {
  constructor(code, message) {
    super(message)
    this.name = 'ProtocolError'
    this.code = code
  }
}

const fail = (code, message) => {
  throw new ProtocolError(code, message)
}

export const isChannel = (v) => CHANNELS.includes(v)
export const isSender = (v) => SENDERS.includes(v)
export const isAgent = (v) => AGENTS.includes(v)

/**
 * Validate and normalize an inbound client message.
 *
 * `time` is deliberately ignored: the server's write time is the only
 * timestamp of record, so a phone with a skewed clock cannot reorder history.
 */
export function normalizeInbound(raw, { now = Date.now() } = {}) {
  if (raw == null || typeof raw !== 'object') fail('bad_payload', 'payload must be an object')
  if (raw.type !== 'message') fail('bad_type', `unsupported type: ${String(raw.type)}`)

  const id = raw.id
  if (typeof id !== 'string' || !UUID_RE.test(id)) {
    fail('bad_id', 'id must be a UUID generated on the client')
  }
  if (!isChannel(raw.channel)) fail('bad_channel', `unknown channel: ${String(raw.channel)}`)

  // Clients may only speak as the user. An app claiming to be ai_a would let
  // anyone forge AI turns straight into history.
  if (raw.sender !== undefined && raw.sender !== 'user') {
    fail('bad_sender', 'clients may only send sender="user"')
  }

  const text = typeof raw.text === 'string' ? raw.text.trim() : ''
  if (!text) fail('empty_text', 'text is required')
  if (text.length > MAX_TEXT_LENGTH) fail('text_too_long', `text exceeds ${MAX_TEXT_LENGTH} chars`)

  const replyTo = raw.replyTo == null ? null : String(raw.replyTo)

  return { id, channel: raw.channel, sender: 'user', text, time: now, replyTo, hop: 0 }
}

/** A message the relay itself creates on an AI's behalf. */
export function makeAgentMessage({ id, channel, sender, text, hop = 0, replyTo = null }, now = Date.now()) {
  if (!isChannel(channel)) fail('bad_channel', `unknown channel: ${String(channel)}`)
  if (!isAgent(sender)) fail('bad_sender', `not an agent: ${String(sender)}`)
  return { id, channel, sender, text, time: now, replyTo, hop }
}

// --- server → client events -------------------------------------------------
export const historyEvent = (channel, messages) => ({ type: 'history', channel, messages })
export const ackEvent = (channel, id, time) => ({ type: 'ack', channel, id, time })
export const deltaEvent = (channel, message) => ({ type: 'delta', channel, message })
export const errorEvent = (code, message, extra = {}) => ({ type: 'error', code, message, ...extra })

/** Per-agent status so the app can show "AI 暂时不可用" instead of spinning forever. */
export const statusEvent = (channel, agent, state, detail = null) => ({
  type: 'status', channel, agent, state, detail,
})

// --- keys -------------------------------------------------------------------
/** ai_a:private, ai_a:group, … — one isolated AI context per key. */
export const contextKey = (agent, channel) => `${agent}:${channel === 'group' ? 'group' : 'private'}`

/** Uniquely identifies "hand this message to this agent". Survives reconnects. */
export const routeKey = (messageId, agent) => `${messageId}:${agent}`
