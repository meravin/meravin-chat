// Local stub. Exercises the whole chain — dedupe, queues, group routing, hop
// limits — without a network call or a cent of API spend. Tests and CI use it.
import { NO_REPLY } from '../protocol.mjs'
import { AdapterError } from './errors.mjs'

export function createEchoAdapter({ name = 'Echo', latencyMs = 0, behavior = null } = {}) {
  let turn = 0

  return {
    id: 'echo',
    name,

    async reply({ systemPrompt, turns, message, contextKey, continuationId }) {
      turn += 1
      if (latencyMs) await new Promise((r) => setTimeout(r, latencyMs))

      // Tests inject a behavior to force a specific outcome.
      if (typeof behavior === 'function') {
        const forced = await behavior({ message, contextKey, turn, turns, systemPrompt })
        if (forced instanceof Error) throw forced
        if (forced !== undefined) {
          return typeof forced === 'string'
            ? { text: forced, continuationId: `${contextKey}#${turn}` }
            : forced
        }
      }

      if (message.text.includes('__FORCE_ERROR__')) {
        throw new AdapterError('unavailable', 'forced failure from echo adapter')
      }
      if (message.text.includes('__FORCE_SILENCE__')) {
        return { text: NO_REPLY, continuationId }
      }

      return {
        text: `[${name}|${contextKey}|turn${turn}] ${message.text}`,
        continuationId: `${contextKey}#${turn}`,
      }
    },
  }
}
