// Transport layer. Everything interesting lives in relay.mjs; this file just
// moves bytes and enforces who is allowed to connect.
import { createServer } from 'node:http'
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { WebSocketServer } from 'ws'

import { openStore } from './store.mjs'
import { createAuth } from './auth.mjs'
import { createQueueSet } from './queue.mjs'
import { createRouter as createMessageRouter } from './router.mjs'
import { buildAdapters, createAgents } from './agents.mjs'
import { createRelay } from './relay.mjs'
import { createWeather } from './weather.mjs'
import { createScheduler } from './scheduler.mjs'
import { createApi } from './api/index.mjs'
import { historyEvent, errorEvent, ProtocolError } from './protocol.mjs'
import { HttpError, sendJson } from './api/http.mjs'

const HERE = dirname(fileURLToPath(import.meta.url))

// Node reads .env natively — no dotenv dependency, and the file stays gitignored.
const envFile = join(HERE, '.env')
if (existsSync(envFile)) process.loadEnvFile(envFile)

/**
 * @param {object} [opts]
 * @param {object} [opts.adapters] injected AI adapters; tests pass echo stubs
 * @param {object} [opts.weather]  injected weather source; tests pass a stub
 */
export async function startServer({
  host = process.env.HOST || '127.0.0.1',
  port = Number(process.env.PORT) || 9191,
  dbPath = process.env.DB_PATH || join(HERE, 'data', 'yourchat.db'),
  token = process.env.YOURCHAT_TOKEN,
  adapters: adapterOverride = null,
  weather: weatherOverride = null,
  log = console,
} = {}) {
  const store = openStore(dbPath)
  const profile = store.getProfile()

  const names = {
    user: profile.userName,
    ai_a: process.env.AI_A_NAME || profile.aiAName,
    ai_b: process.env.AI_B_NAME || profile.aiBName,
  }

  const auth = createAuth({
    token,
    allowedOrigins: (process.env.ALLOWED_ORIGINS ?? '')
      .split(',')
      .map((s) => s.trim())
      .filter(Boolean),
  })

  const adapters = adapterOverride ?? (await buildAdapters({
    ai_a: {
      adapter: process.env.AI_A_ADAPTER || 'claude',
      apiKey: process.env.ANTHROPIC_API_KEY,
      model: process.env.AI_A_MODEL,
      name: names.ai_a,
    },
    ai_b: {
      adapter: process.env.AI_B_ADAPTER || 'openai',
      apiKey: process.env.OPENAI_API_KEY,
      model: process.env.AI_B_MODEL,
      name: names.ai_b,
    },
  }))

  const agents = createAgents({ adapters, names, promptsDir: join(HERE, 'prompts'), store })
  const messageRouter = createMessageRouter({ names })
  const queues = createQueueSet()
  const weather = weatherOverride ?? createWeather()

  /** @type {Set<import('ws').WebSocket>} */
  const clients = new Set()
  const broadcast = (event) => {
    const payload = JSON.stringify(event)
    for (const socket of clients) {
      if (socket.readyState === socket.OPEN) socket.send(payload)
    }
  }

  const relay = createRelay({ store, router: messageRouter, agents, queues, broadcast, log })

  // The scheduler owns backups, which the data routes need; the API owns the
  // whisper generator, which the scheduler needs. Built in that order, then joined.
  const scheduler = createScheduler({ store, dbPath, log })
  const api = createApi({ store, agents, weather, auth, names, backups: scheduler.backups })
  scheduler.setWhisper(api.whisper)
  if (dbPath !== ':memory:') scheduler.start()

  // --- HTTP -----------------------------------------------------------------
  const httpServer = createServer(async (req, res) => {
    const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`)

    if (url.pathname === '/healthz') return sendJson(res, 200, { ok: true })

    const route = api.match(req.method, url.pathname)
    if (!route) return sendJson(res, 404, { error: 'not_found' })

    // The ticket endpoint is the only one reachable with the bearer token alone
    // — everything else needs it too, so the check is uniform.
    const check = auth.check({ headers: req.headers, origin: req.headers.origin })
    if (!check.ok) return sendJson(res, 401, { error: check.reason })

    try {
      await route.handler(req, res, { params: route.params, query: url.searchParams })
    } catch (err) {
      if (err instanceof HttpError) return sendJson(res, err.status, { error: err.code, message: err.message })
      log.error?.('[http]', err)
      return sendJson(res, 500, { error: 'internal_error' })
    }
  })

  // --- WebSocket ------------------------------------------------------------
  const wss = new WebSocketServer({ noServer: true })

  httpServer.on('upgrade', (req, socket, head) => {
    const url = new URL(req.url, `http://${req.headers.host ?? 'localhost'}`)
    const check = auth.check({
      headers: req.headers,
      origin: req.headers.origin,
      ticket: url.searchParams.get('ticket'),
    })
    if (!check.ok) {
      log.warn?.(`[ws] rejected upgrade: ${check.reason}`)
      socket.write('HTTP/1.1 401 Unauthorized\r\nConnection: close\r\n\r\n')
      socket.destroy()
      return
    }
    wss.handleUpgrade(req, socket, head, (ws) => wss.emit('connection', ws, req))
  })

  wss.on('connection', (ws) => {
    clients.add(ws)

    // A reconnecting client gets one page per channel and reconciles locally.
    for (const { channel, messages, cursor } of relay.snapshot()) {
      ws.send(JSON.stringify(historyEvent(channel, messages, cursor)))
    }

    ws.on('message', (data) => {
      let parsed
      try {
        parsed = JSON.parse(data.toString())
      } catch {
        ws.send(JSON.stringify(errorEvent('bad_json', 'frame is not valid JSON')))
        return
      }
      try {
        relay.ingest(parsed, (event) => ws.send(JSON.stringify(event)))
      } catch (err) {
        if (err instanceof ProtocolError) {
          ws.send(JSON.stringify(errorEvent(err.code, err.message, { id: parsed?.id ?? null })))
          return
        }
        log.error?.('[ws]', err)
        ws.send(JSON.stringify(errorEvent('internal_error', 'failed to handle message')))
      }
    })

    ws.on('close', () => clients.delete(ws))
    ws.on('error', () => clients.delete(ws))
  })

  await new Promise((resolve) => httpServer.listen(port, host, resolve))

  const adapterLabel = (agent) => {
    const a = adapters[agent]
    return a ? `${a.id}${a.model ? ` (${a.model})` : ''}` : 'none'
  }
  log.log?.(`[relay] listening on http://${host}:${port}`)
  log.log?.(`[relay] ai_a = ${adapterLabel('ai_a')} · ai_b = ${adapterLabel('ai_b')}`)
  log.log?.(`[relay] weather ${weather.configured ? 'on' : 'off'} · db ${dbPath}`)

  return {
    httpServer,
    wss,
    relay,
    store,
    url: `http://${host}:${port}`,
    async close() {
      scheduler.stop()
      for (const ws of clients) ws.close()
      clients.clear()
      await relay.settle()
      await new Promise((resolve) => wss.close(resolve))
      await new Promise((resolve) => httpServer.close(resolve))
      store.close()
    },
  }
}

// Only auto-start when run directly, so tests can import startServer.
if (process.argv[1] && fileURLToPath(import.meta.url) === process.argv[1]) {
  const server = await startServer()
  const shutdown = async (signal) => {
    console.log(`\n[relay] ${signal} — shutting down`)
    await server.close()
    process.exit(0)
  }
  process.on('SIGINT', () => shutdown('SIGINT'))
  process.on('SIGTERM', () => shutdown('SIGTERM'))
}
