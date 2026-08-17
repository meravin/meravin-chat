// Two things that should happen without anyone opening the app: the day's
// whisper gets written in the morning, and the database gets copied somewhere
// safe. Both are idempotent and keyed by date, so a restart mid-day is fine.
import { readdirSync, unlinkSync, existsSync } from 'node:fs'
import { join, dirname } from 'node:path'
import { todayISO } from './api/dates.mjs'

const TICK_MS = 15 * 60 * 1000
const PREFIX = 'yourchat-'

export function createScheduler({
  store,
  whisper = null,
  dbPath,
  log = console,
  whisperHour = Number(process.env.WHISPER_HOUR ?? 7),
  keepBackups = Number(process.env.KEEP_BACKUPS ?? 14),
}) {
  const backupDir = join(dirname(dbPath), 'backups')
  let timer = null
  let lastBackupDay = null
  // The whisper generator is built by the API layer, which in turn needs this
  // scheduler's `backups` handle — so it is attached after construction.
  let whisperSource = whisper

  const prune = () => {
    if (!existsSync(backupDir)) return
    const files = readdirSync(backupDir)
      .filter((f) => f.startsWith(PREFIX) && f.endsWith('.db'))
      .sort()
      .reverse()
    for (const stale of files.slice(keepBackups)) {
      try {
        unlinkSync(join(backupDir, stale))
      } catch {
        // A backup we can't delete is not worth failing the tick over.
      }
    }
  }

  const backups = {
    /** @param {string} [label] appended to the filename, e.g. "before-erase" */
    async runNow(label = null) {
      const name = label
        ? `${PREFIX}${todayISO()}-${label}-${Date.now()}.db`
        : `${PREFIX}${todayISO()}.db`
      const path = join(backupDir, name)
      await store.backupTo(path)
      prune()
      return path
    },
  }

  async function tick(now = new Date()) {
    const today = todayISO(now)

    // The whisper is the first thing on Home; writing it before the phone is
    // picked up is the difference between "already there" and a spinner.
    if (whisperSource && now.getHours() >= whisperHour && !store.getWhisper(today)) {
      try {
        await whisperSource.forDate(today)
        log.log?.(`[scheduler] wrote whisper for ${today}`)
      } catch (err) {
        log.warn?.(`[scheduler] whisper failed: ${err?.message ?? err}`)
      }
    }

    if (lastBackupDay !== today) {
      try {
        const path = await backups.runNow()
        lastBackupDay = today
        log.log?.(`[scheduler] backed up to ${path}`)
      } catch (err) {
        log.warn?.(`[scheduler] backup failed: ${err?.message ?? err}`)
      }
    }
  }

  return {
    backups,
    tick, // exported for tests, which drive it with a fixed clock
    setWhisper: (source) => { whisperSource = source },

    start() {
      if (timer) return
      // Run once at boot so a relay started after `whisperHour` catches up.
      tick().catch(() => {})
      timer = setInterval(() => tick().catch(() => {}), TICK_MS)
      timer.unref?.() // never hold the process open on its own
    },

    stop() {
      if (timer) clearInterval(timer)
      timer = null
    },
  }
}
