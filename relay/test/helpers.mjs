import { randomUUID } from 'node:crypto'
import { fileURLToPath } from 'node:url'
import { openStore } from '../store.mjs'
import { createRouter } from '../router.mjs'
import { createQueueSet } from '../queue.mjs'
import { createAgents } from '../agents.mjs'
import { createRelay } from '../relay.mjs'
import { createEchoAdapter } from '../adapters/echo.mjs'

const PROMPTS_DIR = fileURLToPath(new URL('../prompts', import.meta.url))

export const NAMES = { user: '我', ai_a: 'Claude', ai_b: 'Codex' }

/**
 * An in-memory relay wired to echo adapters. Exercises the real store, router,
 * queues, and dispatch logic with no sockets and no API spend.
 */
export function makeHarness({ behaviorA, behaviorB, names = NAMES } = {}) {
  const store = openStore(':memory:')
  const router = createRouter({ names })
  const queues = createQueueSet()

  /** Everything the relay pushed to connected clients. */
  const broadcasts = []
  /** Everything sent back on the originating socket (acks). */
  const direct = []

  const agents = createAgents({
    adapters: {
      ai_a: createEchoAdapter({ name: names.ai_a, behavior: behaviorA }),
      ai_b: createEchoAdapter({ name: names.ai_b, behavior: behaviorB }),
    },
    names,
    promptsDir: PROMPTS_DIR,
    store,
  })

  const relay = createRelay({
    store,
    router,
    agents,
    queues,
    broadcast: (e) => broadcasts.push(e),
    log: { warn() {} }, // expected failures are asserted, not printed
  })

  return {
    store,
    relay,
    broadcasts,
    direct,
    close: () => store.close(),

    /** Sends as the user and returns the stored message. */
    send(channel, text, id = randomUUID()) {
      return relay.ingest({ type: 'message', id, channel, text }, (e) => direct.push(e))
    },

    settle: () => relay.settle(),

    of: (type) => broadcasts.filter((e) => e.type === type),
    deltas: (channel) =>
      broadcasts.filter((e) => e.type === 'delta' && e.channel === channel).map((e) => e.message),
    acks: () => direct.filter((e) => e.type === 'ack'),
    statuses: (state) => broadcasts.filter((e) => e.type === 'status' && e.state === state),
  }
}

export const uuid = randomUUID
