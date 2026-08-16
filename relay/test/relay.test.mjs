// The acceptance list from the guide, as executable checks.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { makeHarness, uuid, NAMES } from './helpers.mjs'
import { NO_REPLY } from '../protocol.mjs'

test('a resent UUID is stored once and wakes the AI once', async (t) => {
  let calls = 0
  const h = makeHarness({ behaviorA: () => { calls += 1 } })
  t.after(h.close)

  const id = uuid()
  const first = h.send('ai_a', '你好', id)
  const second = h.send('ai_a', '你好', id) // client retried after a lost ack
  await h.settle()

  assert.equal(first.inserted, true)
  assert.equal(second.inserted, false, 'second insert must be a no-op')
  assert.equal(calls, 1, 'the AI must not be woken twice')
  assert.equal(h.store.history('ai_a').filter((m) => m.id === id).length, 1)

  // Both attempts are still acked, so the client can stop retrying.
  assert.equal(h.acks().filter((a) => a.id === id).length, 2)
})

test('private channels stay isolated from each other', async (t) => {
  const h = makeHarness()
  t.after(h.close)

  h.send('ai_a', 'A 的私聊内容')
  h.send('ai_b', 'B 的私聊内容')
  await h.settle()

  const a = h.store.history('ai_a')
  const b = h.store.history('ai_b')

  assert.ok(a.every((m) => !m.text.includes('B 的私聊内容')))
  assert.ok(b.every((m) => !m.text.includes('A 的私聊内容')))
  assert.ok(a.some((m) => m.sender === 'ai_a'))
  assert.ok(b.some((m) => m.sender === 'ai_b'))
  assert.equal(a.filter((m) => m.sender === 'ai_b').length, 0)
  assert.equal(b.filter((m) => m.sender === 'ai_a').length, 0)
})

test('the four AI contexts are separate', async (t) => {
  const seen = []
  const record = (label) => ({ contextKey }) => { seen.push(`${label}:${contextKey}`) }
  const h = makeHarness({ behaviorA: record('a'), behaviorB: record('b') })
  t.after(h.close)

  h.send('ai_a', '私聊 A')
  h.send('ai_b', '私聊 B')
  h.send('group', '群里说话')
  await h.settle()

  assert.deepEqual(
    [...new Set(seen)].sort(),
    ['a:ai_a:group', 'a:ai_a:private', 'b:ai_b:group', 'b:ai_b:private'],
  )
})

test('a user message in the group wakes both AIs', async (t) => {
  const h = makeHarness()
  t.after(h.close)

  h.send('group', '大家好')
  await h.settle()

  const senders = h.deltas('group').map((m) => m.sender)
  assert.deepEqual(senders.filter((s) => s !== 'user').sort(), ['ai_a', 'ai_b'])
})

test('an @mention gets exactly one extra round, not a loop', async (t) => {
  // AI A always @-mentions Codex; AI B always @-mentions Claude back. Without a
  // hop limit this is an infinite ping-pong.
  const h = makeHarness({
    behaviorA: () => '接着说 @Codex',
    behaviorB: () => '收到 @Claude',
  })
  t.after(h.close)

  h.send('group', '你们聊聊')
  await h.settle()

  const replies = h.deltas('group').filter((m) => m.sender !== 'user')
  const fromA = replies.filter((m) => m.sender === 'ai_a')
  const fromB = replies.filter((m) => m.sender === 'ai_b')

  // Both answer the user at hop 0, and each of those answers @-mentions the
  // other, so both earn exactly one more turn at hop 1. Those hop-1 replies
  // still carry mentions but are no longer forwarded — that is the cap.
  assert.equal(fromA.length, 2, 'AI A: one reply to the user, one to the @mention')
  assert.equal(fromB.length, 2, 'AI B: one reply to the user, one to the @mention')
  assert.deepEqual(fromA.map((m) => m.hop).sort(), [0, 1])
  assert.deepEqual(fromB.map((m) => m.hop).sort(), [0, 1])
  assert.ok(replies.every((m) => m.hop <= 1), 'nothing may exceed hop 1')

  // The real assertion is that settle() returned at all: with mutual mentions
  // and no hop cap this test would never finish.
  assert.equal(replies.length, 4)
})

test('a bare name is not a mention', async (t) => {
  const h = makeHarness({ behaviorA: () => '我昨天问过 Codex 了', behaviorB: () => NO_REPLY })
  t.after(h.close)

  h.send('group', '进度如何')
  await h.settle()

  const fromB = h.deltas('group').filter((m) => m.sender === 'ai_b')
  assert.equal(fromB.length, 0, 'an unmentioned AI must not be woken by its name in prose')
})

test('NO_REPLY is never stored or broadcast', async (t) => {
  const h = makeHarness({ behaviorA: () => NO_REPLY, behaviorB: () => NO_REPLY })
  t.after(h.close)

  h.send('group', '随便说一句')
  await h.settle()

  assert.deepEqual(h.deltas('group').map((m) => m.sender), ['user'])
  assert.equal(h.store.history('group').length, 1)
  assert.ok(!JSON.stringify(h.broadcasts).includes(NO_REPLY))
})

test('a lane is serial: two quick messages keep their order', async (t) => {
  const order = []
  const h = makeHarness({
    // The first reply is deliberately slower than the second.
    behaviorA: async ({ message }) => {
      const slow = message.text.includes('第一条')
      await new Promise((r) => setTimeout(r, slow ? 40 : 1))
      order.push(message.text)
      return `回复：${message.text}`
    },
  })
  t.after(h.close)

  h.send('ai_a', '第一条')
  h.send('ai_a', '第二条')
  await h.settle()

  assert.deepEqual(order, ['第一条', '第二条'], 'the slow first message must still finish first')
  assert.deepEqual(
    h.deltas('ai_a').filter((m) => m.sender === 'ai_a').map((m) => m.text),
    ['回复：第一条', '回复：第二条'],
  )
})

test('an adapter failure surfaces a status and stays retryable', async (t) => {
  let attempts = 0
  const h = makeHarness({
    behaviorA: () => {
      attempts += 1
      if (attempts === 1) return new Error('upstream exploded')
      return '这次成功了'
    },
  })
  t.after(h.close)

  h.send('ai_a', '在吗', uuid())
  await h.settle()

  const errors = h.statuses('error')
  assert.equal(errors.length, 1)
  assert.equal(errors[0].agent, 'ai_a')
  assert.ok(errors[0].detail, 'the app needs something to show instead of a spinner')
  assert.equal(h.deltas('ai_a').filter((m) => m.sender === 'ai_a').length, 0)

  // The route claim was released, so a fresh send is answered normally.
  h.send('ai_a', '在吗', uuid())
  await h.settle()
  assert.equal(attempts, 2)
  assert.equal(h.deltas('ai_a').filter((m) => m.sender === 'ai_a').length, 1)
})

test('an AI never consumes its own message', async (t) => {
  const h = makeHarness({ behaviorA: () => '自言自语 @Claude', behaviorB: () => NO_REPLY })
  t.after(h.close)

  h.send('group', '开始')
  await h.settle()

  // A mentioning itself must not schedule another AI A round.
  assert.equal(h.deltas('group').filter((m) => m.sender === 'ai_a').length, 1)
})

test('history is returned oldest-first and paginates backwards', async (t) => {
  const h = makeHarness({ behaviorA: () => NO_REPLY })
  t.after(h.close)

  for (let i = 0; i < 5; i += 1) h.send('ai_a', `第 ${i} 条`)
  await h.settle()

  const all = h.store.history('ai_a', { limit: 10 })
  assert.deepEqual(all.map((m) => m.text), ['第 0 条', '第 1 条', '第 2 条', '第 3 条', '第 4 条'])

  const lastTwo = h.store.history('ai_a', { limit: 2 })
  assert.deepEqual(lastTwo.map((m) => m.text), ['第 3 条', '第 4 条'])
})

test('the group prompt labels every speaker and names the trigger', async (t) => {
  let captured = null
  const h = makeHarness({ behaviorA: ({ turns }) => { captured = turns[0].content; return NO_REPLY } })
  t.after(h.close)

  h.send('group', '这句话要出现在记录里')
  await h.settle()

  assert.match(captured, new RegExp(`${NAMES.user}：这句话要出现在记录里`))
  assert.match(captured, /本轮触发你的消息/)
  assert.match(captured, new RegExp(NO_REPLY))
})
