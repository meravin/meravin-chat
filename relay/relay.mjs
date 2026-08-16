// The traffic controller. Persist → ack → wake the right AI, in that order, so
// an app that sends and immediately loses signal never loses a message and can
// safely retry with the same UUID.
import { randomUUID } from 'node:crypto'
import {
  ackEvent,
  contextKey,
  deltaEvent,
  makeAgentMessage,
  normalizeInbound,
  routeKey,
  statusEvent,
} from './protocol.mjs'
import { HISTORY_TURNS } from './agents.mjs'
import { AdapterError } from './adapters/errors.mjs'

export function createRelay({ store, router, agents, queues, broadcast, log = console }) {
  /** @type {Set<Promise<unknown>>} in-flight routes, so tests can await settle */
  const inflight = new Set()

  const track = (p) => {
    inflight.add(p)
    p.finally(() => inflight.delete(p))
    return p
  }

  async function runRoute(trigger, agent) {
    const key = routeKey(trigger.id, agent)
    const { channel } = trigger

    try {
      broadcast(statusEvent(channel, agent, 'thinking'))

      const history = store.history(channel, { limit: HISTORY_TURNS })
      const today = new Date().toISOString().slice(0, 10)

      const { text, silent } = await agents.reply({
        agent,
        channel,
        message: trigger,
        history,
        today,
        health: store.latestHealth(),
      })

      broadcast(statusEvent(channel, agent, 'idle'))

      // NO_REPLY means the AI chose not to speak. Store nothing, send nothing —
      // the marker must never reach the app.
      if (silent || !router.shouldBroadcast(text)) return null

      const reply = makeAgentMessage({
        id: randomUUID(),
        channel,
        sender: agent,
        text,
        hop: router.replyHop(trigger),
        replyTo: trigger.id,
      })

      const { message: stored } = store.saveMessage(reply)
      broadcast(deltaEvent(channel, stored))

      // An AI reply can itself be routed — but only one more hop, and only on
      // an explicit @mention. `replyHop` is what makes that terminate.
      dispatch(stored)
      return stored
    } catch (err) {
      // Let the client retry: without releasing the claim, one transient
      // failure would silently block this message from ever being answered.
      store.releaseRouteJob(key)

      const detail = err instanceof AdapterError ? err.userFacing : 'AI 暂时不可用'
      log.warn?.(`[relay] ${agent} on ${channel} failed: ${err?.message ?? err}`)
      broadcast(statusEvent(channel, agent, 'error', detail))
      return null
    }
  }

  /** Hands a stored message to every agent that should see it. Never throws. */
  function dispatch(message) {
    const targets = router.targets(message)
    const runs = []

    for (const agent of targets) {
      if (!agents.has(agent)) continue

      // <message-id>:<agent> is claimed exactly once. A reconnect that resends
      // the same UUID loses the race here and triggers nothing.
      const key = routeKey(message.id, agent)
      if (!store.claimRouteJob(key)) continue

      // One serial lane per channel+agent; separate lanes run in parallel.
      runs.push(track(queues.run(contextKey(agent, message.channel), () => runRoute(message, agent))))
    }
    return runs
  }

  return {
    dispatch,

    /**
     * Handle one inbound client frame.
     * @param {unknown} raw parsed JSON from the socket
     * @param {(event: object) => void} send reply channel for this client only
     */
    ingest(raw, send) {
      const incoming = normalizeInbound(raw)

      // 1. persist first
      const { message, inserted } = store.saveMessage(incoming)
      // 2. then ack, so a client that drops now knows it got through
      send(ackEvent(message.channel, message.id, message.time))
      // 3. and only then wake the AIs — and only for a genuinely new message
      if (inserted) {
        broadcast(deltaEvent(message.channel, message))
        dispatch(message)
      }
      return { message, inserted }
    },

    /** Initial payload after a (re)connect: one page per channel. */
    snapshot(limit = HISTORY_TURNS) {
      return ['ai_a', 'ai_b', 'group'].map((channel) => ({
        channel,
        messages: store.history(channel, { limit }),
      }))
    },

    /** Waits for every in-flight AI round. Tests and shutdown use this. */
    async settle() {
      while (inflight.size) await Promise.allSettled([...inflight])
      await queues.drain()
    },
  }
}
