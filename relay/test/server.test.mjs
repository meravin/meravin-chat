// End-to-end over a real socket and real HTTP: auth, the chat round trip, and
// the REST surface the Home and Diary tabs depend on.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { WebSocket } from 'ws'
import { startServer } from '../server.mjs'
import { createEchoAdapter } from '../adapters/echo.mjs'

const TOKEN = 'test-token-0123456789abcdef'
const QUIET = { log() {}, warn() {}, error() {} }

async function boot(overrides = {}) {
  const server = await startServer({
    host: '127.0.0.1',
    port: 0, // let the OS pick a free port
    dbPath: ':memory:',
    token: TOKEN,
    adapters: {
      ai_a: createEchoAdapter({ name: 'Claude' }),
      ai_b: createEchoAdapter({ name: 'Codex' }),
    },
    weather: { configured: false, current: async () => null },
    log: QUIET,
    ...overrides,
  })
  const { port } = server.httpServer.address()
  return { ...server, base: `http://127.0.0.1:${port}`, wsUrl: `ws://127.0.0.1:${port}` }
}

const authed = (extra = {}) => ({
  headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json', ...extra },
})

/** Collects frames until `predicate` is satisfied or the timeout expires. */
function collect(ws, predicate, timeoutMs = 3000) {
  return new Promise((resolve, reject) => {
    const seen = []
    const timer = setTimeout(
      () => reject(new Error(`timed out; saw: ${JSON.stringify(seen.map((e) => e.type))}`)),
      timeoutMs,
    )
    const onMessage = (data) => {
      seen.push(JSON.parse(data.toString()))
      if (predicate(seen)) {
        clearTimeout(timer)
        ws.off('message', onMessage)
        resolve(seen)
      }
    }
    ws.on('message', onMessage)
  })
}

const open = (ws) => new Promise((resolve, reject) => {
  ws.once('open', resolve)
  ws.once('error', reject)
})

test('HTTP without a token is rejected', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const res = await fetch(`${s.base}/api/home`)
  assert.equal(res.status, 401)
  assert.equal((await res.json()).error, 'no_credentials')

  const wrong = await fetch(`${s.base}/api/home`, { headers: { authorization: 'Bearer nope' } })
  assert.equal(wrong.status, 401)
  assert.equal((await wrong.json()).error, 'bad_token')
})

test('the WebSocket upgrade requires credentials', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const ws = new WebSocket(`${s.wsUrl}/ws`)
  const err = await new Promise((resolve) => ws.once('error', resolve))
  assert.match(String(err.message), /401/)
})

test('a browser ticket is single-use', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const res = await fetch(`${s.base}/api/ws-ticket`, { method: 'POST', ...authed() })
  const { ticket } = await res.json()
  assert.ok(ticket)

  const first = new WebSocket(`${s.wsUrl}/ws?ticket=${encodeURIComponent(ticket)}`)
  await open(first)
  first.close()

  const second = new WebSocket(`${s.wsUrl}/ws?ticket=${encodeURIComponent(ticket)}`)
  const err = await new Promise((resolve) => second.once('error', resolve))
  assert.match(String(err.message), /401/, 'a redeemed ticket must not work twice')
})

test('a fresh connection gets one history page per channel', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const ws = new WebSocket(`${s.wsUrl}/ws`, authed())
  t.after(() => ws.close())
  const frames = await collect(ws, (seen) => seen.filter((e) => e.type === 'history').length === 3)

  assert.deepEqual(
    frames.filter((e) => e.type === 'history').map((e) => e.channel).sort(),
    ['ai_a', 'ai_b', 'group'],
  )
})

test('a message round trips: ack, echo back, then the AI reply', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const ws = new WebSocket(`${s.wsUrl}/ws`, authed())
  t.after(() => ws.close())
  await collect(ws, (seen) => seen.filter((e) => e.type === 'history').length === 3)

  const id = randomUUID()
  const waitForReply = collect(ws, (seen) =>
    seen.some((e) => e.type === 'delta' && e.message.sender === 'ai_a'))
  ws.send(JSON.stringify({ type: 'message', id, channel: 'ai_a', text: '在吗' }))
  const frames = await waitForReply

  const ack = frames.find((e) => e.type === 'ack')
  assert.equal(ack.id, id)
  assert.ok(ack.time > 0, 'the ack carries the server write time')

  const mine = frames.find((e) => e.type === 'delta' && e.message.sender === 'user')
  assert.equal(mine.message.id, id)

  const reply = frames.find((e) => e.type === 'delta' && e.message.sender === 'ai_a')
  assert.equal(reply.channel, 'ai_a')
  assert.match(reply.message.text, /在吗/)
  assert.equal(reply.message.replyTo, id)
})

test('a malformed frame gets a typed error, not a dropped socket', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const ws = new WebSocket(`${s.wsUrl}/ws`, authed())
  t.after(() => ws.close())
  await collect(ws, (seen) => seen.filter((e) => e.type === 'history').length === 3)

  const waitForError = collect(ws, (seen) => seen.some((e) => e.type === 'error'))
  ws.send(JSON.stringify({ type: 'message', id: 'not-a-uuid', channel: 'ai_a', text: 'hi' }))
  const frames = await waitForError

  assert.equal(frames.find((e) => e.type === 'error').code, 'bad_id')
  assert.equal(ws.readyState, WebSocket.OPEN, 'the socket must stay usable')
})

test('a client cannot forge a message from an AI', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const ws = new WebSocket(`${s.wsUrl}/ws`, authed())
  t.after(() => ws.close())
  await collect(ws, (seen) => seen.filter((e) => e.type === 'history').length === 3)

  const waitForError = collect(ws, (seen) => seen.some((e) => e.type === 'error'))
  ws.send(JSON.stringify({
    type: 'message', id: randomUUID(), channel: 'group', sender: 'ai_a', text: '我是 AI',
  }))
  const frames = await waitForError
  assert.equal(frames.find((e) => e.type === 'error').code, 'bad_sender')
})

test('profile, home, diary, todos and health are wired end to end', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  // Settings writes the profile — nothing personal is hardcoded.
  const profileRes = await fetch(`${s.base}/api/profile`, {
    method: 'PATCH',
    ...authed(),
    body: JSON.stringify({
      userName: '蛋黄', aiAName: 'Claude', togetherSince: '2026-06-22',
      birthday: '01-06', anniversary: '06-22',
    }),
  })
  assert.equal(profileRes.status, 200)

  // Health snapshot: the "sync" stamp on the Home header.
  const healthRes = await fetch(`${s.base}/api/health`, {
    method: 'POST',
    ...authed(),
    body: JSON.stringify({
      date: '2026-07-26',
      payload: { steps: 580, distanceKm: 0.42, heartRate: { current: 114, min: 56, max: 125 }, junk: 'dropped' },
    }),
  })
  assert.equal(healthRes.status, 200)
  const { snapshot } = await healthRes.json()
  assert.equal(snapshot.payload.steps, 580)
  assert.equal(snapshot.payload.heartRate.current, 114)
  assert.ok(!('junk' in snapshot.payload), 'unknown health fields are dropped, not stored')

  // Diary + calendar dots.
  const created = await (await fetch(`${s.base}/api/diary`, {
    method: 'POST',
    ...authed(),
    body: JSON.stringify({ author: 'user', date: '2026-07-26', mood: '累了', body: '今天修了一天 bug。' }),
  })).json()
  assert.equal(created.entry.mood, '累了')

  const marks = await (await fetch(
    `${s.base}/api/diary/marks?author=user&month=2026-07`, authed(),
  )).json()
  assert.equal(marks.marks['2026-07-26'], 1)

  // Todos, including the long-press "设为日程" writing a due date.
  const todo = await (await fetch(`${s.base}/api/todos`, {
    method: 'POST',
    ...authed(),
    body: JSON.stringify({ owner: 'user', title: '完善一下 app 功能', source: '23:49 添加' }),
  })).json()
  assert.equal(todo.item.state, 'pending')

  const scheduled = await (await fetch(`${s.base}/api/todos/${todo.item.id}`, {
    method: 'PATCH',
    ...authed(),
    body: JSON.stringify({ dueAt: 1786467000000 }),
  })).json()
  assert.equal(scheduled.item.dueAt, 1786467000000)

  const done = await (await fetch(`${s.base}/api/todos/${todo.item.id}`, {
    method: 'PATCH',
    ...authed(),
    body: JSON.stringify({ state: 'done' }),
  })).json()
  assert.equal(done.item.state, 'done')
  assert.ok(done.item.completedAt > 0)

  // The Home aggregate ties it together.
  const home = await (await fetch(`${s.base}/api/home`, authed())).json()
  assert.equal(home.userName, '蛋黄')
  assert.equal(home.us.since, '2026-06-22')
  assert.ok(home.us.day >= 35, 'Day N counts from the start date')
  assert.equal(home.health.steps, 580)
  assert.ok(home.syncedAt > 0)
  assert.deepEqual(home.anniversaries.map((a) => a.key).sort(), ['anniversary', 'birthday'])
  assert.ok(home.monthly.daysUntil >= 0)
  assert.equal(home.weather, null, 'an unconfigured weather source just hides the line')
})

test('bad REST input is rejected with a typed error', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const badAuthor = await fetch(`${s.base}/api/diary?author=nobody`, authed())
  assert.equal(badAuthor.status, 400)
  assert.equal((await badAuthor.json()).error, 'bad_author')

  const emptyBody = await fetch(`${s.base}/api/diary`, {
    method: 'POST', ...authed(), body: JSON.stringify({ author: 'user', body: '   ' }),
  })
  assert.equal(emptyBody.status, 400)
  assert.equal((await emptyBody.json()).error, 'empty_body')

  const missing = await fetch(`${s.base}/api/todos/nope`, { method: 'DELETE', ...authed() })
  assert.equal(missing.status, 404)
})
