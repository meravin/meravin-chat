#!/usr/bin/env node
// Terminal client for the relay. Lets you walk the whole acceptance list —
// three channels, dedupe, group routing, AI status — before the iOS app exists.
//
//   node tools/cli-client.mjs
//   YOURCHAT_TOKEN=... RELAY_URL=ws://127.0.0.1:9191 node tools/cli-client.mjs
import { createInterface } from 'node:readline'
import { randomUUID } from 'node:crypto'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { WebSocket } from 'ws'

const HERE = dirname(fileURLToPath(import.meta.url))
const envFile = join(HERE, '..', '.env')
if (existsSync(envFile)) process.loadEnvFile(envFile)

const TOKEN = process.env.YOURCHAT_TOKEN
const URL_ = process.env.RELAY_URL || `ws://${process.env.HOST || '127.0.0.1'}:${process.env.PORT || 9191}/ws`

if (!TOKEN) {
  console.error('YOURCHAT_TOKEN is not set (put it in relay/.env or pass it inline)')
  process.exit(1)
}

const C = {
  dim: (s) => `\x1b[2m${s}\x1b[0m`,
  bold: (s) => `\x1b[1m${s}\x1b[0m`,
  user: (s) => `\x1b[36m${s}\x1b[0m`,
  aiA: (s) => `\x1b[35m${s}\x1b[0m`,
  aiB: (s) => `\x1b[33m${s}\x1b[0m`,
  warn: (s) => `\x1b[31m${s}\x1b[0m`,
  ok: (s) => `\x1b[32m${s}\x1b[0m`,
}

const CHANNEL_LABEL = { ai_a: 'AI A 私聊', ai_b: 'AI B 私聊', group: '群聊' }
const paint = { user: C.user, ai_a: C.aiA, ai_b: C.aiB }

let channel = 'group'
/** Sent but not yet acked — the CLI's stand-in for the app's outbox. */
const pending = new Map()

const rl = createInterface({ input: process.stdin, output: process.stdout })
const prompt = () => {
  rl.setPrompt(`${C.bold(CHANNEL_LABEL[channel])} ${C.dim('>')} `)
  rl.prompt()
}

const line = (text) => {
  process.stdout.write(`\r\x1b[K${text}\n`)
  prompt()
}

const render = (m, { historic = false } = {}) => {
  const who = paint[m.sender]?.(m.sender) ?? m.sender
  const hop = m.hop > 0 ? C.dim(` hop${m.hop}`) : ''
  const mark = historic ? C.dim('·') : ' '
  line(`${mark} ${who}${hop} ${C.dim('│')} ${m.text}`)
}

console.log(C.dim(`connecting to ${URL_} …`))
const ws = new WebSocket(URL_, { headers: { authorization: `Bearer ${TOKEN}` } })

ws.on('open', () => {
  line(C.ok('已连接。') + C.dim('  /a 私聊A  /b 私聊B  /g 群聊  /r 重发未确认  /q 退出'))
})

ws.on('message', (data) => {
  const event = JSON.parse(data.toString())

  switch (event.type) {
    case 'history':
      if (event.channel !== channel) return
      line(C.dim(`── ${CHANNEL_LABEL[event.channel]} 历史 (${event.messages.length}) ──`))
      event.messages.forEach((m) => render(m, { historic: true }))
      return

    case 'ack': {
      pending.delete(event.id)
      return
    }

    case 'delta':
      if (event.channel !== channel) {
        line(C.dim(`（${CHANNEL_LABEL[event.channel]} 有新消息）`))
        return
      }
      render(event.message)
      return

    case 'status':
      if (event.channel !== channel) return
      if (event.state === 'error') line(C.warn(`⚠ ${event.agent}：${event.detail}`))
      return

    case 'error':
      line(C.warn(`✖ ${event.code}: ${event.message}`))
      return

    default:
      line(C.dim(`? ${JSON.stringify(event)}`))
  }
})

ws.on('close', () => {
  line(C.warn('连接已断开。'))
  process.exit(0)
})
ws.on('error', (err) => {
  line(C.warn(`连接失败：${err.message}`))
  process.exit(1)
})

const send = (text, id = randomUUID()) => {
  const frame = { type: 'message', id, channel, text }
  pending.set(id, frame)
  ws.send(JSON.stringify(frame))
}

rl.on('line', (raw) => {
  const text = raw.trim()
  if (!text) return prompt()

  switch (text) {
    case '/q':
      ws.close()
      return rl.close()
    case '/a': case '/b': case '/g':
      channel = { '/a': 'ai_a', '/b': 'ai_b', '/g': 'group' }[text]
      line(C.dim(`切到 ${CHANNEL_LABEL[channel]}`))
      return
    case '/r':
      // Resending the same UUIDs must not produce duplicate AI replies.
      if (!pending.size) return line(C.dim('没有未确认的消息'))
      line(C.dim(`重发 ${pending.size} 条未确认消息（相同 UUID）`))
      for (const frame of pending.values()) ws.send(JSON.stringify(frame))
      return
    default:
      send(text)
      prompt()
  }
})

rl.on('close', () => process.exit(0))
