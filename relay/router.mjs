// Who should see a new message, and what stops two AIs talking forever.
//
//   new message from │ to AI A              │ to AI B
//   ─────────────────┼──────────────────────┼──────────────────────
//   user             │ yes                  │ yes
//   AI A             │ no                   │ only on explicit @AI B
//   AI B             │ only on explicit @AI A │ no
//
// Plus three hard rules:
//   1. An AI never consumes a message it just wrote.
//   2. Once a forwarded message has hop >= 1, it is not auto-forwarded again.
//   3. An adapter may answer NO_REPLY; the relay then stores and sends nothing.
import { AGENTS, NO_REPLY } from './protocol.mjs'

const OTHER = { ai_a: 'ai_b', ai_b: 'ai_a' }

/** Generic handles always work; display names are configurable per install. */
const handlesFor = (agent, names) => {
  const generic = agent === 'ai_a' ? ['ai a', 'ai_a', 'aia'] : ['ai b', 'ai_b', 'aib']
  const display = names?.[agent] ? [String(names[agent]).toLowerCase()] : []
  return [...generic, ...display]
}

const escapeRe = (s) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

/**
 * True when `text` addresses `agent` with an explicit @mention. Bare occurrences
 * of the name don't count — "I asked Claude yesterday" must not wake anyone.
 */
export function mentionsAgent(text, agent, names = {}) {
  if (typeof text !== 'string' || !text) return false
  const haystack = text.toLowerCase()
  return handlesFor(agent, names).some((handle) => {
    const re = new RegExp(`@\\s*${escapeRe(handle)}(?![\\p{L}\\p{N}_])`, 'u')
    return re.test(haystack)
  })
}

/**
 * Which agents should be woken by this message.
 * @returns {Array<'ai_a'|'ai_b'>}
 */
export function routeTargets(message, { names = {} } = {}) {
  const { channel, sender, hop = 0, text } = message

  // Private channels: only the user drives them, and only their own AI answers.
  if (channel === 'ai_a' || channel === 'ai_b') {
    return sender === 'user' ? [channel] : []
  }

  if (channel !== 'group') return []

  // A user turn in the group wakes both AIs; each decides independently whether
  // to speak, and whoever finishes first is displayed first.
  if (sender === 'user') return [...AGENTS]

  // From here on the sender is an AI.
  if (hop >= 1) return [] // rule 2: this reply may not start a third round
  if (!AGENTS.includes(sender)) return []

  const other = OTHER[sender]
  return mentionsAgent(text, other, names) ? [other] : [] // rule 1 is implicit: never `sender`
}

/**
 * Hop for a reply. A reply the user triggered stays at 0 so the conversation
 * can keep going; an AI-triggered reply increments, which is what caps the
 * exchange at exactly one extra round.
 */
export const replyHop = (trigger) => (trigger.sender === 'user' ? 0 : (trigger.hop ?? 0) + 1)

/** NO_REPLY (and empty output) never reaches history or the app. */
export const shouldBroadcast = (text) =>
  typeof text === 'string' && text.trim() !== '' && text.trim() !== NO_REPLY

export function createRouter({ names = {} } = {}) {
  return {
    names,
    targets: (message) => routeTargets(message, { names }),
    mentions: (text, agent) => mentionsAgent(text, agent, names),
    replyHop,
    shouldBroadcast,
  }
}
