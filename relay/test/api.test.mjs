// The pull-side surface: older pages, search, extraction, export, erase, and
// the scheduled jobs.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { randomUUID } from 'node:crypto'
import { mkdtempSync, rmSync, readdirSync, existsSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { join } from 'node:path'
import { openStore } from '../store.mjs'
import { createScheduler } from '../scheduler.mjs'
import { todayISO } from '../api/dates.mjs'
import { startServer } from '../server.mjs'
import { createEchoAdapter } from '../adapters/echo.mjs'

const TOKEN = 'test-token-0123456789abcdef'
const QUIET = { log() {}, warn() {}, error() {} }
const authed = (extra = {}) => ({
  headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json', ...extra },
})

async function boot(adapters) {
  const server = await startServer({
    host: '127.0.0.1',
    port: 0,
    dbPath: ':memory:',
    token: TOKEN,
    adapters: adapters ?? {
      ai_a: createEchoAdapter({ name: 'Claude' }),
      ai_b: createEchoAdapter({ name: 'Codex' }),
    },
    weather: { configured: false, current: async () => null },
    log: QUIET,
  })
  const { port } = server.httpServer.address()
  return { ...server, base: `http://127.0.0.1:${port}` }
}

const seedDiary = (base, body, date = todayISO()) =>
  fetch(`${base}/api/diary`, {
    method: 'POST', ...authed(),
    body: JSON.stringify({ author: 'user', date, body }),
  }).then((r) => r.json())

test('older pages come back through the before cursor', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  // 12 stored messages, no AI replies to keep the arithmetic obvious.
  for (let i = 0; i < 12; i += 1) {
    s.store.saveMessage({
      id: randomUUID(), channel: 'ai_a', sender: 'user',
      text: `第 ${i} 条`, time: 1_700_000_000_000 + i * 1000, replyTo: null, hop: 0,
    })
  }

  const first = await (await fetch(`${s.base}/api/messages?channel=ai_a&limit=5`, authed())).json()
  assert.deepEqual(first.messages.map((m) => m.text), ['第 7 条', '第 8 条', '第 9 条', '第 10 条', '第 11 条'])
  assert.equal(first.hasMore, true)

  const older = await (await fetch(
    `${s.base}/api/messages?channel=ai_a&limit=5&before=${first.messages[0].time}`, authed(),
  )).json()
  assert.deepEqual(older.messages.map((m) => m.text), ['第 2 条', '第 3 条', '第 4 条', '第 5 条', '第 6 条'])

  const last = await (await fetch(
    `${s.base}/api/messages?channel=ai_a&limit=5&before=${older.messages[0].time}`, authed(),
  )).json()
  assert.deepEqual(last.messages.map((m) => m.text), ['第 0 条', '第 1 条'])
  assert.equal(last.hasMore, false, 'a short page means there is nothing older')
})

test('pagination rejects a bad channel or cursor', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  const badChannel = await fetch(`${s.base}/api/messages?channel=nope`, authed())
  assert.equal((await badChannel.json()).error, 'bad_channel')

  const badCursor = await fetch(`${s.base}/api/messages?channel=ai_a&before=soon`, authed())
  assert.equal((await badCursor.json()).error, 'bad_cursor')
})

test('search covers both messages and diary entries', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  s.store.saveMessage({
    id: randomUUID(), channel: 'group', sender: 'user',
    text: '卡片透明度调到 85% 就对了', time: Date.now(), replyTo: null, hop: 0,
  })
  await seedDiary(s.base, '今天把卡片透明度重新调了一遍，终于不闷了。')
  await seedDiary(s.base, '完全无关的一篇。')

  const found = await (await fetch(`${s.base}/api/search?q=${encodeURIComponent('透明度')}`, authed())).json()
  assert.equal(found.messages.length, 1)
  assert.equal(found.diary.length, 1)
  assert.match(found.diary[0].excerpt, /透明度/)

  const nothing = await (await fetch(`${s.base}/api/search?q=zzzznotfound`, authed())).json()
  assert.deepEqual([nothing.messages.length, nothing.diary.length], [0, 0])

  const empty = await fetch(`${s.base}/api/search?q=`, authed())
  assert.equal(empty.status, 400)
})

test('a LIKE wildcard in the query is matched literally', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  await seedDiary(s.base, '进度 100% 完成')
  await seedDiary(s.base, '完全不含百分号的一篇')

  // Unescaped, "%" would match every row.
  const found = await (await fetch(`${s.base}/api/search?q=${encodeURIComponent('100%')}`, authed())).json()
  assert.equal(found.diary.length, 1)
})

test('todo extraction proposes candidates without writing any', async (t) => {
  const s = await boot({
    ai_a: createEchoAdapter({
      name: 'Claude',
      behavior: () => '1. 修 pulse 的框型 bug\n- 测试苹果充值是否恢复\n\n给日记加导出',
    }),
    ai_b: createEchoAdapter({ name: 'Codex' }),
  })
  t.after(() => s.close())

  const { entry } = await seedDiary(s.base, '今天修到半夜，pulse 的框还是歪的。', '2026-07-25')

  const before = await (await fetch(`${s.base}/api/todos?owner=user`, authed())).json()
  const result = await (await fetch(`${s.base}/api/diary/${entry.id}/todos`, {
    method: 'POST', ...authed(),
  })).json()

  assert.deepEqual(result.candidates,
    ['修 pulse 的框型 bug', '测试苹果充值是否恢复', '给日记加导出'],
    'numbering and bullet prefixes are stripped')
  assert.equal(result.source, '7月25日记的')

  const after = await (await fetch(`${s.base}/api/todos?owner=user`, authed())).json()
  assert.equal(after.items.length, before.items.length, 'extraction must not create todos itself')
})

test('a failing model yields no candidates, not a broken diary', async (t) => {
  const s = await boot({
    ai_a: createEchoAdapter({ name: 'Claude', behavior: () => new Error('upstream down') }),
    ai_b: createEchoAdapter({ name: 'Codex' }),
  })
  t.after(() => s.close())

  const { entry } = await seedDiary(s.base, '随便写点什么。')
  const res = await fetch(`${s.base}/api/diary/${entry.id}/todos`, { method: 'POST', ...authed() })

  assert.equal(res.status, 200)
  assert.deepEqual((await res.json()).candidates, [])
})

test('export contains everything and erase needs the phrase', async (t) => {
  const s = await boot()
  t.after(() => s.close())

  await seedDiary(s.base, '要被导出的一篇')
  s.store.saveMessage({
    id: randomUUID(), channel: 'ai_a', sender: 'user',
    text: '要被导出的一条', time: Date.now(), replyTo: null, hop: 0,
  })

  const res = await fetch(`${s.base}/api/export`, authed())
  assert.match(res.headers.get('content-disposition') ?? '', /attachment; filename="yourchat-\d{4}-\d{2}-\d{2}\.json"/)

  const bundle = await res.json()
  assert.equal(bundle.version, 1)
  assert.equal(bundle.messages.length, 1)
  assert.equal(bundle.diary.length, 1)
  assert.ok(bundle.profile)

  // Erase without the phrase changes nothing.
  const refused = await fetch(`${s.base}/api/data`, {
    method: 'DELETE', ...authed(), body: JSON.stringify({ confirm: 'yes' }),
  })
  assert.equal(refused.status, 400)
  assert.equal((await refused.json()).error, 'confirmation_required')
  assert.equal(s.store.history('ai_a').length, 1, 'nothing erased')

  const done = await fetch(`${s.base}/api/data`, {
    method: 'DELETE', ...authed(), body: JSON.stringify({ confirm: 'ERASE' }),
  })
  assert.equal(done.status, 200)
  const { erased, backup } = await done.json()
  assert.equal(erased.messages, 1)
  assert.ok(backup, 'a safety copy is taken before erasing')

  assert.equal(s.store.history('ai_a').length, 0)
  assert.ok(s.store.getProfile().aiAName, 'the profile survives so the app still knows whose it is')

  rmSync(backup, { force: true })
})

test('the scheduler writes one whisper a day and prunes old backups', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'yourchat-sched-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))

  const store = openStore(join(dir, 'db.sqlite'))
  t.after(() => store.close())

  let generated = 0
  const scheduler = createScheduler({
    store,
    dbPath: join(dir, 'db.sqlite'),
    log: QUIET,
    whisperHour: 7,
    keepBackups: 2,
    whisper: {
      forDate: async (date) => {
        generated += 1
        return store.putWhisper(date, `写于 ${date}`, 'ai_a')
      },
    },
  })

  const at = (hour) => new Date(2026, 7, 17, hour, 0, 0)

  await scheduler.tick(at(6))
  assert.equal(generated, 0, 'too early — nothing written before whisperHour')

  await scheduler.tick(at(7))
  assert.equal(generated, 1)
  assert.match(store.getWhisper(todayISO(at(7))).text, /写于/)

  await scheduler.tick(at(9))
  await scheduler.tick(at(21))
  assert.equal(generated, 1, 'later ticks must not rewrite the day')

  // The daily backup ran once; extra manual ones get pruned to keepBackups.
  const backupDir = join(dir, 'backups')
  assert.ok(existsSync(backupDir))
  await scheduler.backups.runNow('manual-a')
  await scheduler.backups.runNow('manual-b')
  await scheduler.backups.runNow('manual-c')
  assert.equal(readdirSync(backupDir).length, 2, 'only the newest keepBackups survive')
})

test('a backup is a real, readable database', async (t) => {
  const dir = mkdtempSync(join(tmpdir(), 'yourchat-backup-'))
  t.after(() => rmSync(dir, { recursive: true, force: true }))

  const dbPath = join(dir, 'db.sqlite')
  const store = openStore(dbPath)
  store.saveMessage({
    id: randomUUID(), channel: 'group', sender: 'user',
    text: '这条要出现在备份里', time: Date.now(), replyTo: null, hop: 0,
  })

  const copy = join(dir, 'copy.sqlite')
  await store.backupTo(copy)
  store.close()

  const restored = openStore(copy)
  t.after(() => restored.close())
  assert.equal(restored.history('group')[0].text, '这条要出现在备份里')
})
