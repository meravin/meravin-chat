// AI A. Everything vendor-specific stays behind the shared reply() contract, so
// swapping providers later means editing this file and its env vars — not the
// message protocol and not the app.
import Anthropic from '@anthropic-ai/sdk'
import { AdapterError, fromHttpStatus } from './errors.mjs'

const DEFAULT_MODEL = 'claude-opus-5'
// Thinking is on by default on Opus 5 and max_tokens caps thinking + reply
// together, so this needs headroom well past the length of a chat message.
const DEFAULT_MAX_TOKENS = 4096

export function createClaudeAdapter({
  apiKey = process.env.ANTHROPIC_API_KEY,
  model = process.env.AI_A_MODEL || DEFAULT_MODEL,
  effort = process.env.AI_A_EFFORT || 'medium',
  maxTokens = Number(process.env.AI_A_MAX_TOKENS) || DEFAULT_MAX_TOKENS,
  name = 'Claude',
  timeoutMs = 90_000,
} = {}) {
  if (!apiKey) {
    throw new AdapterError('config', 'ANTHROPIC_API_KEY is not set (AI A)')
  }
  const client = new Anthropic({ apiKey, timeout: timeoutMs, maxRetries: 2 })

  return {
    id: 'claude',
    name,
    model,

    async reply({ systemPrompt, turns, signal }) {
      let response
      try {
        response = await client.messages.create(
          {
            model,
            max_tokens: maxTokens,
            // Persona text is stable across turns, so cache it and pay ~0.1x
            // on every later message in the conversation.
            system: [{ type: 'text', text: systemPrompt, cache_control: { type: 'ephemeral' } }],
            thinking: { type: 'adaptive' },
            output_config: { effort },
            messages: turns,
          },
          { signal },
        )
      } catch (err) {
        if (err instanceof Anthropic.APIError) {
          throw fromHttpStatus(err.status ?? 0, `Claude: ${err.message}`, err)
        }
        if (err?.name === 'AbortError') throw new AdapterError('timeout', 'Claude: aborted', { cause: err })
        throw new AdapterError('unavailable', `Claude: ${err?.message ?? err}`, { cause: err })
      }

      // Check the stop reason before touching content: on a refusal `content`
      // is empty or partial, so indexing straight into it would throw.
      if (response.stop_reason === 'refusal') {
        const category = response.stop_details?.category ?? 'unspecified'
        throw new AdapterError('refusal', `Claude declined (${category})`)
      }

      const text = response.content
        .filter((block) => block.type === 'text')
        .map((block) => block.text)
        .join('')
        .trim()

      if (!text) {
        const why = response.stop_reason === 'max_tokens' ? 'hit max_tokens' : 'no text block'
        throw new AdapterError('empty', `Claude returned no text (${why})`)
      }

      // The Messages API is stateless — the relay's stored history is the only
      // source of truth, so there is no continuation id to carry forward.
      return { text, continuationId: null }
    },
  }
}
