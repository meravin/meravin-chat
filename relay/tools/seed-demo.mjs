#!/usr/bin/env node
// Fills a running relay with plausible demo data so the app's screens can be
// checked without waiting for real HealthKit samples or a month of diaries.
//
//   node tools/seed-demo.mjs
//
// Safe to re-run: everything is keyed by id or date, so it overwrites rather
// than duplicating. Never point this at a relay holding real conversations.
import { existsSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { randomUUID } from 'node:crypto'
import { WebSocket } from 'ws'

const HERE = dirname(fileURLToPath(import.meta.url))
const envFile = join(HERE, '..', '.env')
if (existsSync(envFile)) process.loadEnvFile(envFile)

const TOKEN = process.env.YOURCHAT_TOKEN
const BASE = process.env.RELAY_HTTP || `http://${process.env.HOST || '127.0.0.1'}:${process.env.PORT || 9191}`
const WS_URL = BASE.replace(/^http/, 'ws') + '/ws'

if (!TOKEN) {
  console.error('YOURCHAT_TOKEN is not set')
  process.exit(1)
}

const api = async (method, path, body) => {
  const res = await fetch(BASE + path, {
    method,
    headers: { authorization: `Bearer ${TOKEN}`, 'content-type': 'application/json' },
    body: body ? JSON.stringify(body) : undefined,
  })
  if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${await res.text()}`)
  return res.json()
}

// Local date parts, not toISOString(): east of UTC the latter reports
// yesterday for most of the morning and every date lands off by one.
const iso = (d) =>
  `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
const daysAgo = (n) => {
  const d = new Date()
  d.setDate(d.getDate() - n)
  return d
}

// --- profile: Day 35 today, with two countdowns ------------------------------
await api('PATCH', '/api/profile', {
  userName: '敏敏',
  aiAName: 'Claude',
  aiBName: 'Codex',
  groupName: '我们仨',
  togetherSince: iso(daysAgo(34)),
  birthday: '01-06',
  anniversary: '06-22',
})

// --- health snapshot ---------------------------------------------------------
await api('POST', '/api/health', {
  date: iso(new Date()),
  payload: {
    steps: 580,
    distanceKm: 0.42,
    stepsByWeekday: [4210, 3180, 5020, 2870, 1240, 860, 580],
    heartRate: {
      current: 114,
      min: 56,
      max: 125,
      series: Array.from({ length: 60 }, (_, i) =>
        72 + Math.sin(i / 4) * 14 + (i > 44 ? (i - 44) * 2.4 : 0)),
    },
    sleep: {
      minutes: 182,
      start: new Date(new Date().setHours(12, 7, 0, 0)).toISOString(),
      end: new Date(new Date().setHours(16, 9, 0, 0)).toISOString(),
      stages: [
        { stage: 'deep', minutes: 38 },
        { stage: 'core', minutes: 96 },
        { stage: 'rem', minutes: 41 },
        { stage: 'awake', minutes: 7 },
      ],
    },
    cycle: { day: 21, length: 29, nextExpected: iso(daysAgo(-8)) },
    body: { oxygen: 96, hrv: 20, temperature: 36.5, weightKg: 44.5 },
  },
})

// --- diaries -----------------------------------------------------------------
const diaries = [
  { author: 'user', day: 0, mood: '累了', body: '今天从早修到夜里十一点半。删除确认气泡跑到屏幕顶上，我们挂在整页上试了三种方案才对。' },
  { author: 'user', day: 1, mood: '开心', body: '把首页的卡片透明度调到 85%，一下子就对了。之前一直觉得哪里闷，原来是卡片压得太实。' },
  { author: 'user', day: 4, mood: '平静', body: '什么都没干，看了一下午的雨。' },
  { author: 'ai_a', day: 0, mood: '累了', body: '今天几乎一整天都泡在聊天页的地基里。从一句「模型按钮卡在 Opus 5」开始，一路挖到估高漂移的老病根，把换地基线合了进来。\n\n中间我猜错过两次方向，最后的解法是把思考链拆成独立的行，观感还她，机制换新。' },
  { author: 'ai_a', day: 2, mood: '有劲', body: '记两条帐：合成点击这条路废了，别再用；她的录屏比我的任何推理都准，以后先要录屏再动刀。' },
]
for (const d of diaries) {
  await api('POST', '/api/diary', {
    author: d.author, date: iso(daysAgo(d.day)), mood: d.mood, body: d.body,
  })
}

// --- todos -------------------------------------------------------------------
const todos = [
  { owner: 'user', title: '完善一下 app 功能', source: '7月25日记的' },
  { owner: 'user', title: 'todo list 完成勾选没有取消选项', source: '7月25日记的' },
  { owner: 'user', title: '修 pulse 的框型 bug', source: '23:49 添加' },
  { owner: 'user', title: '是否可以让你做个向量检索', source: '7月21日记的' },
  { owner: 'ai_a', title: '测试苹果充值是否恢复', source: '7月20日记的' },
]
for (const t of todos) await api('POST', '/api/todos', t)

// --- a few messages on each channel -----------------------------------------
const socket = new WebSocket(WS_URL, { headers: { authorization: `Bearer ${TOKEN}` } })
await new Promise((resolve, reject) => {
  socket.once('open', resolve)
  socket.once('error', reject)
})

const say = (channel, text) =>
  new Promise((resolve) => {
    socket.send(JSON.stringify({ type: 'message', id: randomUUID(), channel, text }))
    setTimeout(resolve, 220) // let the echo adapter answer before the next line
  })

await say('ai_a', '把你今天写的东西动过的东西告诉我')
await say('ai_b', '为什么上下滑动聊天记录的时候会卡')
await say('group', '找到了。首页那个「Claude」的卡片没有跟着皮肤走')

socket.close()
console.log('seeded: profile, health, diary, todos, and three channels of chat')
