// AI B. Same reply() contract as the Claude adapter — the relay can't tell them
// apart, which is the point: changing providers never touches the app or the
// message protocol.
import OpenAI from 'openai'
import { AdapterError, fromHttpStatus } from './errors.mjs'

const DEFAULT_MAX_TOKENS = 2048

export function createOpenAIAdapter({
  apiKey = process.env.OPENAI_API_KEY,
  model = process.env.AI_B_MODEL,
  baseURL = process.env.AI_B_ENDPOINT || undefined,
  maxTokens = Number(process.env.AI_B_MAX_TOKENS) || DEFAULT_MAX_TOKENS,
  name = 'Codex',
  timeoutMs = 90_000,
} = {}) {
  if (!apiKey) throw new AdapterError('config', 'OPENAI_API_KEY is not set (AI B)')
  if (!model) throw new AdapterError('config', 'AI_B_MODEL is not set (AI B)')

  const client = new OpenAI({ apiKey, baseURL, timeout: timeoutMs, maxRetries: 2 })

  return {
    id: 'openai',
    name,
    model,

    async reply({ systemPrompt, turns, signal }) {
      // chat.completions is the broadest-compatibility surface across model
      // generations; the shared `turns` shape maps onto it unchanged.
      const messages = [{ role: 'system', content: systemPrompt }, ...turns]

      let response
      try {
        response = await client.chat.completions.create(
          { model, messages, max_completion_tokens: maxTokens },
          { signal },
        )
      } catch (err) {
        if (err instanceof OpenAI.APIError) {
          throw fromHttpStatus(err.status ?? 0, `OpenAI: ${err.message}`, err)
        }
        if (err?.name === 'AbortError') throw new AdapterError('timeout', 'OpenAI: aborted', { cause: err })
        throw new AdapterError('unavailable', `OpenAI: ${err?.message ?? err}`, { cause: err })
      }

      const choice = response.choices?.[0]
      if (choice?.finish_reason === 'content_filter') {
        throw new AdapterError('refusal', 'OpenAI: filtered by content policy')
      }

      const text = (choice?.message?.content ?? '').trim()
      if (!text) {
        const why = choice?.finish_reason === 'length' ? 'hit the token cap' : 'no content'
        throw new AdapterError('empty', `OpenAI returned no text (${why})`)
      }

      return { text, continuationId: null }
    },
  }
}
