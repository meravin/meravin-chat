// One interface in front of both AIs. The relay hands over a system prompt, the
// history it already stores, and this round's message; it gets back plain text.
// Nothing above this layer knows which vendor answered.
import { readFileSync, existsSync } from 'node:fs'
import { join } from 'node:path'
import { NO_REPLY, contextKey } from './protocol.mjs'
import { AdapterError } from './adapters/errors.mjs'

export const HISTORY_TURNS = 30

const PROMPT_FILES = { ai_a: 'ai-a', ai_b: 'ai-b' }

/**
 * Real personas live in prompts/ai-a.md (gitignored). The committed
 * .example.md is a neutral placeholder so a fresh clone still runs.
 */
export function loadPersona(agent, promptsDir) {
  const base = PROMPT_FILES[agent]
  if (!base) throw new AdapterError('config', `unknown agent: ${agent}`)
  for (const file of [`${base}.md`, `${base}.example.md`]) {
    const path = join(promptsDir, file)
    if (existsSync(path)) return readFileSync(path, 'utf8').trim()
  }
  throw new AdapterError('config', `no persona file for ${agent} in ${promptsDir}`)
}

const displayName = (who, names) =>
  who === 'user' ? (names.user ?? '我') : (names[who] ?? who)

/** Compact, only-what-changed context. Skipped entirely when there's no data. */
function todayBlock({ today, health }) {
  const lines = []
  if (today) lines.push(`今天是 ${today}。`)
  if (health) {
    const h = health.payload ?? {}
    const bits = []
    if (h.steps != null) bits.push(`步数 ${h.steps}`)
    if (h.heartRate?.current != null) bits.push(`心率 ${h.heartRate.current} bpm`)
    if (h.sleep?.minutes != null) bits.push(`睡眠 ${Math.floor(h.sleep.minutes / 60)}h${h.sleep.minutes % 60}m`)
    if (h.cycle?.day != null) bits.push(`生理周期第 ${h.cycle.day} 天`)
    if (bits.length) lines.push(`她今天的身体数据：${bits.join('、')}。`)
  }
  if (!lines.length) return ''
  return `\n\n<today>\n${lines.join('\n')}\n</today>`
}

const PRIVATE_RULES = `
<output_rules>
只输出要显示在聊天里的正文。不要输出名字前缀、引号包裹、JSON 或任何内部说明。
</output_rules>`

const groupRules = (self, names) => `
<group_chat>
这是一个三人群聊，成员：${names.user ?? '我'}、${names.ai_a ?? 'AI A'}、${names.ai_b ?? 'AI B'}。你是 ${names[self] ?? self}。

- 不是每条消息都必须回复。当你不适合插话时，只输出 ${NO_REPLY}，不要输出任何别的内容。
- 只输出要显示在聊天里的正文。不要输出名字前缀、发言人标签、JSON 或内部说明。
- 想让另一位 AI 接话时，在正文里明确 @ 对方；否则你的发言不会转给对方。
</group_chat>`

/** Renders group history as a labelled transcript instead of alternating turns. */
function transcript(history, names) {
  if (!history.length) return '（群聊还没有消息）'
  return history
    .map((m) => `[${m.id.slice(0, 8)}] ${displayName(m.sender, names)}：${m.text}`)
    .join('\n')
}

/**
 * Build the system prompt and the turns array for one agent.
 * @returns {{ systemPrompt: string, turns: Array<{role: string, content: string}> }}
 */
export function buildPrompt({ agent, channel, history, message, persona, names, today, health }) {
  const context = todayBlock({ today, health })

  if (channel === 'group') {
    const systemPrompt = persona + groupRules(agent, names) + context
    const trigger = `本轮触发你的消息：[${message.id.slice(0, 8)}] ${displayName(message.sender, names)}`
    const turns = [
      {
        role: 'user',
        content:
          `最近的群聊记录（每行标注了发送者）：\n\n${transcript(history, names)}\n\n` +
          `${trigger}\n\n请以 ${names[agent] ?? agent} 的身份回应，或者输出 ${NO_REPLY}。`,
      },
    ]
    return { systemPrompt, turns }
  }

  // Private channel: a normal two-party conversation maps cleanly onto turns.
  const systemPrompt = persona + PRIVATE_RULES + context
  const turns = []
  for (const m of history) {
    turns.push({ role: m.sender === agent ? 'assistant' : 'user', content: m.text })
  }
  // The APIs require the first turn to be `user`.
  while (turns.length && turns[0].role !== 'user') turns.shift()
  if (!turns.length || turns.at(-1).content !== message.text) {
    turns.push({ role: 'user', content: message.text })
  }
  return { systemPrompt, turns }
}

/**
 * @param {object} opts
 * @param {{ai_a: object, ai_b: object}} opts.adapters  objects exposing reply()
 */
export function createAgents({ adapters, names = {}, promptsDir = 'prompts', store = null }) {
  const personaCache = new Map()

  const persona = (agent) => {
    if (!personaCache.has(agent)) personaCache.set(agent, loadPersona(agent, promptsDir))
    return personaCache.get(agent)
  }

  return {
    names,
    promptsDir,
    has: (agent) => Boolean(adapters[agent]),
    adapterFor: (agent) => adapters[agent],
    reloadPersonas: () => personaCache.clear(),

    /**
     * Ask one agent for a reply.
     * @returns {Promise<{text: string, silent: boolean}>}
     */
    async reply({ agent, channel, message, history, today = null, health = null, signal }) {
      const adapter = adapters[agent]
      if (!adapter) throw new AdapterError('config', `no adapter configured for ${agent}`)

      const key = contextKey(agent, channel)
      const { systemPrompt, turns } = buildPrompt({
        agent,
        channel,
        history,
        message,
        persona: persona(agent),
        names,
        today,
        health,
      })

      const result = await adapter.reply({
        systemPrompt,
        turns,
        message,
        contextKey: key,
        continuationId: store?.getContext(key) ?? null,
        signal,
      })

      if (store && result.continuationId) store.setContext(key, result.continuationId)

      const text = (result.text ?? '').trim()
      return { text, silent: text === '' || text === NO_REPLY }
    },
  }
}

/** Chooses an adapter from env, falling back to the local echo stub. */
export async function buildAdapters(config) {
  const { createEchoAdapter } = await import('./adapters/echo.mjs')
  const out = {}

  for (const [agent, cfg] of Object.entries(config)) {
    if (!cfg || cfg.adapter === 'none') continue
    if (cfg.adapter === 'echo') {
      out[agent] = createEchoAdapter({ name: cfg.name })
      continue
    }
    try {
      if (cfg.adapter === 'claude') {
        const { createClaudeAdapter } = await import('./adapters/claude.mjs')
        out[agent] = createClaudeAdapter(cfg)
      } else if (cfg.adapter === 'openai') {
        const { createOpenAIAdapter } = await import('./adapters/openai.mjs')
        out[agent] = createOpenAIAdapter(cfg)
      } else {
        throw new AdapterError('config', `unknown adapter: ${cfg.adapter}`)
      }
    } catch (err) {
      // A missing key must not stop the relay from booting — the chain still
      // works end to end on echo, and the app shows a clear per-agent status.
      console.warn(`[agents] ${agent}: ${err.message} — falling back to echo`)
      out[agent] = createEchoAdapter({ name: cfg.name })
    }
  }
  return out
}
