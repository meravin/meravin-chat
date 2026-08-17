// The relay is the single writer for everything the app shows. AI adapters hand
// their result back to the relay; they never touch these tables themselves.
import { DatabaseSync, backup } from 'node:sqlite'
import { mkdirSync } from 'node:fs'
import { dirname } from 'node:path'

const SCHEMA = `
PRAGMA journal_mode = WAL;
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS messages (
  id       TEXT PRIMARY KEY,
  channel  TEXT NOT NULL,
  sender   TEXT NOT NULL,
  text     TEXT NOT NULL,
  time     INTEGER NOT NULL,
  reply_to TEXT,
  hop      INTEGER NOT NULL DEFAULT 0
);
-- rowid is implicit and cannot be named in an index; queries still tie-break on
-- it so two messages written in the same millisecond keep their insert order.
CREATE INDEX IF NOT EXISTS messages_channel_time ON messages (channel, time);

-- One row per "this message has been handed to this agent". Keyed by
-- <message-id>:<target-agent> so a reconnect that resends the same UUID can
-- never trigger a second reply.
CREATE TABLE IF NOT EXISTS route_jobs (
  key     TEXT PRIMARY KEY,
  done_at INTEGER NOT NULL
);

-- Four rows in practice: ai_a:private, ai_a:group, ai_b:private, ai_b:group.
-- Keeping them apart is what stops private talk leaking into the group chat.
CREATE TABLE IF NOT EXISTS contexts (
  key             TEXT PRIMARY KEY,
  continuation_id TEXT,
  updated_at      INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS diary_entries (
  id         TEXT PRIMARY KEY,
  author     TEXT NOT NULL,
  date       TEXT NOT NULL,
  mood       TEXT,
  body       TEXT NOT NULL,
  created_at INTEGER NOT NULL,
  updated_at INTEGER NOT NULL
);
CREATE INDEX IF NOT EXISTS diary_author_date ON diary_entries (author, date DESC);

CREATE TABLE IF NOT EXISTS todos (
  id           TEXT PRIMARY KEY,
  owner        TEXT NOT NULL,
  title        TEXT NOT NULL,
  source       TEXT,
  state        TEXT NOT NULL DEFAULT 'pending',
  due_at       INTEGER,
  created_at   INTEGER NOT NULL,
  completed_at INTEGER
);
CREATE INDEX IF NOT EXISTS todos_owner_state ON todos (owner, state, created_at DESC);

CREATE TABLE IF NOT EXISTS health_snapshots (
  date      TEXT PRIMARY KEY,
  payload   TEXT NOT NULL,
  synced_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS whispers (
  date       TEXT PRIMARY KEY,
  text       TEXT NOT NULL,
  author     TEXT NOT NULL,
  created_at INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS profile (
  k TEXT PRIMARY KEY,
  v TEXT NOT NULL
);
`

// Placeholders only. The app's Settings screen writes the real values, so
// nothing personal is ever baked into the source.
const PROFILE_DEFAULTS = {
  userName: 'You',
  aiAName: 'Claude',
  aiBName: 'Codex',
  groupName: '我们仨',
  togetherSince: '',
  birthday: '',
  anniversary: '',
  // Launch screen. `signature` is the name written in script as you drag;
  // empty means "use userName". `epigraph` is the line under the dedication —
  // blank by default, because that sentence should be the owner's, not ours.
  signature: '',
  epigraph: '',
}

/** `"<ms>.<rowid>"` → `{time, rowId}`; anything malformed reads as "no cursor". */
function parseCursor(cursor) {
  if (cursor == null || cursor === '') return null
  const [time, rowId] = String(cursor).split('.').map(Number)
  if (!Number.isFinite(time) || !Number.isFinite(rowId)) return null
  return { time, rowId }
}

export function openStore(path = 'data/yourchat.db') {
  if (path !== ':memory:') mkdirSync(dirname(path), { recursive: true })
  const db = new DatabaseSync(path)
  db.exec(SCHEMA)

  const seedProfile = db.prepare('INSERT OR IGNORE INTO profile (k, v) VALUES (?, ?)')
  for (const [k, v] of Object.entries(PROFILE_DEFAULTS)) seedProfile.run(k, v)

  const q = {
    insertMessage: db.prepare(
      `INSERT OR IGNORE INTO messages (id, channel, sender, text, time, reply_to, hop)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ),
    getMessage: db.prepare('SELECT * FROM messages WHERE id = ?'),
    historyTail: db.prepare(
      `SELECT * FROM messages WHERE channel = ?
       ORDER BY time DESC, rowid DESC LIMIT ?`,
    ),
    // Two-part cursor. A plain `time <` skips every sibling written in the
    // same millisecond — routine in the group, where both AIs can land
    // together — and those messages then become permanently unreachable.
    historyBefore: db.prepare(
      `SELECT * FROM messages
       WHERE channel = ? AND (time < ? OR (time = ? AND rowid < ?))
       ORDER BY time DESC, rowid DESC LIMIT ?`,
    ),
    historyTailWithRow: db.prepare(
      `SELECT rowid AS row_id, * FROM messages WHERE channel = ?
       ORDER BY time DESC, rowid DESC LIMIT ?`,
    ),
    historyBeforeWithRow: db.prepare(
      `SELECT rowid AS row_id, * FROM messages
       WHERE channel = ? AND (time < ? OR (time = ? AND rowid < ?))
       ORDER BY time DESC, rowid DESC LIMIT ?`,
    ),

    claimJob: db.prepare('INSERT OR IGNORE INTO route_jobs (key, done_at) VALUES (?, ?)'),
    releaseJob: db.prepare('DELETE FROM route_jobs WHERE key = ?'),

    getContext: db.prepare('SELECT continuation_id FROM contexts WHERE key = ?'),
    setContext: db.prepare(
      `INSERT INTO contexts (key, continuation_id, updated_at) VALUES (?, ?, ?)
       ON CONFLICT(key) DO UPDATE SET continuation_id = excluded.continuation_id,
                                      updated_at = excluded.updated_at`,
    ),

    listDiary: db.prepare(
      `SELECT * FROM diary_entries WHERE author = ?
       ORDER BY date DESC, created_at DESC LIMIT ?`,
    ),
    listDiaryByDate: db.prepare(
      'SELECT * FROM diary_entries WHERE author = ? AND date = ? ORDER BY created_at ASC',
    ),
    diaryMarks: db.prepare(
      `SELECT date, COUNT(*) AS n FROM diary_entries
       WHERE author = ? AND date LIKE ? GROUP BY date`,
    ),
    insertDiary: db.prepare(
      `INSERT INTO diary_entries (id, author, date, mood, body, created_at, updated_at)
       VALUES (?, ?, ?, ?, ?, ?, ?)`,
    ),
    updateDiary: db.prepare(
      `UPDATE diary_entries
       SET mood = COALESCE(?, mood), body = COALESCE(?, body), updated_at = ?
       WHERE id = ?`,
    ),
    deleteDiary: db.prepare('DELETE FROM diary_entries WHERE id = ?'),
    getDiary: db.prepare('SELECT * FROM diary_entries WHERE id = ?'),

    listTodos: db.prepare(
      'SELECT * FROM todos WHERE owner = ? ORDER BY created_at DESC LIMIT ?',
    ),
    insertTodo: db.prepare(
      `INSERT INTO todos (id, owner, title, source, state, due_at, created_at, completed_at)
       VALUES (?, ?, ?, ?, ?, ?, ?, NULL)`,
    ),
    updateTodo: db.prepare(
      `UPDATE todos
       SET title = COALESCE(?, title), state = COALESCE(?, state),
           due_at = CASE WHEN ? THEN ? ELSE due_at END,
           completed_at = ?
       WHERE id = ?`,
    ),
    deleteTodo: db.prepare('DELETE FROM todos WHERE id = ?'),
    getTodo: db.prepare('SELECT * FROM todos WHERE id = ?'),

    putHealth: db.prepare(
      `INSERT INTO health_snapshots (date, payload, synced_at) VALUES (?, ?, ?)
       ON CONFLICT(date) DO UPDATE SET payload = excluded.payload,
                                       synced_at = excluded.synced_at`,
    ),
    getHealth: db.prepare('SELECT * FROM health_snapshots WHERE date = ?'),
    latestHealth: db.prepare('SELECT * FROM health_snapshots ORDER BY date DESC LIMIT 1'),

    getWhisper: db.prepare('SELECT * FROM whispers WHERE date = ?'),
    putWhisper: db.prepare(
      `INSERT INTO whispers (date, text, author, created_at) VALUES (?, ?, ?, ?)
       ON CONFLICT(date) DO UPDATE SET text = excluded.text, author = excluded.author,
                                       created_at = excluded.created_at`,
    ),

    allProfile: db.prepare('SELECT k, v FROM profile'),
    setProfile: db.prepare(
      `INSERT INTO profile (k, v) VALUES (?, ?)
       ON CONFLICT(k) DO UPDATE SET v = excluded.v`,
    ),

    // LIKE with an escaped pattern: fine at personal scale, and it avoids
    // maintaining an FTS index that would need rebuilding on every schema change.
    searchMessages: db.prepare(
      `SELECT * FROM messages WHERE text LIKE ? ESCAPE '\\'
       ORDER BY time DESC LIMIT ?`,
    ),
    searchDiary: db.prepare(
      `SELECT * FROM diary_entries WHERE body LIKE ? ESCAPE '\\'
       ORDER BY date DESC, created_at DESC LIMIT ?`,
    ),
  }

  const toMessage = (row) =>
    row && {
      id: row.id,
      channel: row.channel,
      sender: row.sender,
      text: row.text,
      time: row.time,
      replyTo: row.reply_to ?? null,
      hop: row.hop,
    }

  const toDiary = (row) =>
    row && {
      id: row.id,
      author: row.author,
      date: row.date,
      mood: row.mood ?? null,
      body: row.body,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }

  const toTodo = (row) =>
    row && {
      id: row.id,
      owner: row.owner,
      title: row.title,
      source: row.source ?? null,
      state: row.state,
      dueAt: row.due_at ?? null,
      createdAt: row.created_at,
      completedAt: row.completed_at ?? null,
    }

  return {
    db,
    close: () => db.close(),

    // --- messages -----------------------------------------------------------
    // Returns { message, inserted }. `inserted: false` means this UUID was
    // already stored — the caller still acks, but must not wake an AI again.
    saveMessage(msg) {
      const res = q.insertMessage.run(
        msg.id,
        msg.channel,
        msg.sender,
        msg.text,
        msg.time,
        msg.replyTo ?? null,
        msg.hop ?? 0,
      )
      const stored = toMessage(q.getMessage.get(msg.id))
      return { message: stored, inserted: res.changes === 1 }
    },

    getMessage: (id) => toMessage(q.getMessage.get(id)),

    // Newest page first, returned oldest-first so the client can append.
    history(channel, { limit = 50, before = null } = {}) {
      const rows = before == null
        ? q.historyTail.all(channel, limit)
        : q.historyBefore.all(channel, before.time, before.time, before.rowId, limit)
      return rows.map(toMessage).reverse()
    },

    /**
     * A page plus the cursor for the page before it. The cursor is `time.rowid`
     * so messages sharing a millisecond stay individually addressable.
     * @returns {{messages: object[], cursor: string|null, hasMore: boolean}}
     */
    historyPage(channel, { limit = 30, cursor = null } = {}) {
      const parsed = parseCursor(cursor)
      const rows = parsed == null
        ? q.historyTailWithRow.all(channel, limit)
        : q.historyBeforeWithRow.all(channel, parsed.time, parsed.time, parsed.rowId, limit)

      // Rows arrive newest-first; the last one is the oldest in this page and
      // therefore the cursor for whatever comes before it.
      const oldest = rows.at(-1)
      return {
        messages: rows.map(toMessage).reverse(),
        cursor: oldest ? `${oldest.time}.${oldest.row_id}` : null,
        hasMore: rows.length === limit,
      }
    },

    // --- route jobs ---------------------------------------------------------
    // True only for the caller that won the key. Everyone else skips the work.
    claimRouteJob(key, now = Date.now()) {
      return q.claimJob.run(key, now).changes === 1
    },
    releaseRouteJob: (key) => void q.releaseJob.run(key),

    // --- AI contexts --------------------------------------------------------
    getContext: (key) => q.getContext.get(key)?.continuation_id ?? null,
    setContext: (key, continuationId, now = Date.now()) =>
      void q.setContext.run(key, continuationId ?? null, now),

    // --- diary --------------------------------------------------------------
    listDiary: (author, limit = 60) => q.listDiary.all(author, limit).map(toDiary),
    listDiaryByDate: (author, date) => q.listDiaryByDate.all(author, date).map(toDiary),
    // { 'YYYY-MM-DD': count } for the month calendar's dots.
    diaryMarks(author, yearMonth) {
      const out = {}
      for (const row of q.diaryMarks.all(author, `${yearMonth}-%`)) out[row.date] = row.n
      return out
    },
    createDiary({ id, author, date, mood = null, body }, now = Date.now()) {
      q.insertDiary.run(id, author, date, mood, body, now, now)
      return toDiary(q.getDiary.get(id))
    },
    updateDiary(id, { mood, body } = {}, now = Date.now()) {
      q.updateDiary.run(mood ?? null, body ?? null, now, id)
      return toDiary(q.getDiary.get(id))
    },
    deleteDiary: (id) => q.deleteDiary.run(id).changes === 1,
    getDiary: (id) => toDiary(q.getDiary.get(id)),

    // --- todos --------------------------------------------------------------
    listTodos: (owner, limit = 100) => q.listTodos.all(owner, limit).map(toTodo),
    createTodo({ id, owner, title, source = null, dueAt = null }, now = Date.now()) {
      q.insertTodo.run(id, owner, title, source, 'pending', dueAt, now)
      return toTodo(q.getTodo.get(id))
    },
    updateTodo(id, { title, state, dueAt } = {}, now = Date.now()) {
      const touchDue = dueAt !== undefined
      const completedAt = state === 'done' ? now : state === 'pending' ? null : (q.getTodo.get(id)?.completed_at ?? null)
      q.updateTodo.run(title ?? null, state ?? null, touchDue ? 1 : 0, touchDue ? dueAt : null, completedAt, id)
      return toTodo(q.getTodo.get(id))
    },
    deleteTodo: (id) => q.deleteTodo.run(id).changes === 1,
    getTodo: (id) => toTodo(q.getTodo.get(id)),

    // --- health -------------------------------------------------------------
    putHealth(date, payload, now = Date.now()) {
      q.putHealth.run(date, JSON.stringify(payload), now)
      return { date, payload, syncedAt: now }
    },
    getHealth(date) {
      const row = q.getHealth.get(date)
      return row && { date: row.date, payload: JSON.parse(row.payload), syncedAt: row.synced_at }
    },
    latestHealth() {
      const row = q.latestHealth.get()
      return row && { date: row.date, payload: JSON.parse(row.payload), syncedAt: row.synced_at }
    },

    // --- whisper ------------------------------------------------------------
    getWhisper(date) {
      const row = q.getWhisper.get(date)
      return row && { date: row.date, text: row.text, author: row.author, createdAt: row.created_at }
    },
    putWhisper(date, text, author, now = Date.now()) {
      q.putWhisper.run(date, text, author, now)
      return { date, text, author, createdAt: now }
    },

    // --- profile ------------------------------------------------------------
    getProfile() {
      const out = {}
      for (const row of q.allProfile.all()) out[row.k] = row.v
      return out
    },
    setProfile(patch) {
      for (const [k, v] of Object.entries(patch)) {
        if (v != null) q.setProfile.run(k, String(v))
      }
      return this.getProfile()
    },

    // --- search -------------------------------------------------------------
    search(query, limit = 40) {
      // Escape the LIKE wildcards so a literal % or _ in the query matches itself.
      const pattern = `%${String(query).replace(/[\\%_]/g, '\\$&')}%`
      return {
        messages: q.searchMessages.all(pattern, limit).map(toMessage),
        diary: q.searchDiary.all(pattern, limit).map(toDiary),
      }
    },

    // --- export & erase -----------------------------------------------------
    /** Everything the app owns, in one JSON-serialisable object. */
    exportAll() {
      const table = (name) => db.prepare(`SELECT * FROM ${name}`).all()
      return {
        exportedAt: new Date().toISOString(),
        version: 1,
        profile: this.getProfile(),
        messages: table('messages').map(toMessage),
        diary: table('diary_entries').map(toDiary),
        todos: table('todos').map(toTodo),
        health: table('health_snapshots').map((r) => ({
          date: r.date, payload: JSON.parse(r.payload), syncedAt: r.synced_at,
        })),
        whispers: table('whispers'),
      }
    },

    /**
     * Deletes every conversation, diary, todo, and health row. Keeps the
     * profile so the app still knows who it belongs to after a wipe.
     */
    eraseAll() {
      const tables = ['messages', 'route_jobs', 'contexts', 'diary_entries',
        'todos', 'health_snapshots', 'whispers']
      const counts = {}
      // All or nothing: a crash midway would otherwise leave AI contexts
      // pointing at messages that no longer exist.
      db.exec('BEGIN IMMEDIATE')
      try {
        for (const name of tables) {
          counts[name] = db.prepare(`SELECT COUNT(*) n FROM ${name}`).get().n
          db.exec(`DELETE FROM ${name}`)
        }
        db.exec('COMMIT')
      } catch (err) {
        db.exec('ROLLBACK')
        throw err
      }
      return counts
    },

    /** Point-in-time copy, safe to run while the relay is serving. */
    async backupTo(path) {
      mkdirSync(dirname(path), { recursive: true })
      await backup(db, path)
      return path
    },
  }
}
