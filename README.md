# YourChat

An iOS chat app with three conversations — two private AIs and a group with both
— plus a Home dashboard built on HealthKit and a two-person diary.

Two pieces:

```
relay/   Node.js message bridge — WebSocket + REST, SQLite, two AI adapters
ios/     SwiftUI app — Home / Chats / Diary, six skins, HealthKit
```

**No AI credential ever reaches the app.** The phone holds one relay token, in
the Keychain; the Anthropic and OpenAI keys stay in `relay/.env` on the machine
running the bridge.

---

## Run it

### 1. The relay

```bash
cd relay && npm install
```

```bash
cp .env.example .env
```

Fill in `.env`. The token is the one credential the app needs — generate it with:

```bash
openssl rand -hex 32
```

Then start the bridge:

```bash
cd relay && npm start
```

It listens on `127.0.0.1:9191` and prints which adapter each AI resolved to. A
missing API key is not fatal: that agent falls back to the local `echo` stub so
the whole chain still runs.

Personas live in `relay/prompts/`. Copy `ai-a.example.md` → `ai-a.md` (and the
same for B) and write your own; the real files are gitignored.

### 2. The app

```bash
cp ios/YourChat/Config/Secrets.example.swift ios/YourChat/Config/Secrets.swift
```

Put the same token in it, then generate and open the project:

```bash
brew install xcodegen && cd ios && xcodegen generate && open YourChat.xcodeproj
```

`Secrets.swift` only seeds the first launch — after that the host, TLS switch,
and token are editable in **Settings → 消息桥** and the token lives in the
Keychain.

In Xcode, pick your Team under Signing & Capabilities before running on a real
iPhone. The simulator needs no signing.

### 3. Demo data (optional)

To see the screens populated without waiting for real HealthKit samples:

```bash
cd relay && node tools/seed-demo.mjs
```

Never run that against a relay holding real conversations.

---

## Checking it works

```bash
cd relay && npm test
```

45 checks covering the parts that are easy to get subtly wrong: a resent UUID
stores once and wakes an AI once — but does retry a route whose first attempt
failed; private channels can't leak into each other; the four AI contexts stay
separate; an `@mention` earns exactly one extra round instead of an infinite
loop; a lane stays serial under load; an adapter failure surfaces a status
instead of an endless spinner; paging walks history to the beginning and stops,
including through messages that share a millisecond; a `%` in a search query
matches literally; todo extraction proposes without writing; an erase refuses
without its confirmation phrase; and the scheduler writes one whisper a day and
prunes old backups.

For a hands-on pass, `node tools/cli-client.mjs` gives you the three channels in
the terminal — `/a` `/b` `/g` to switch, `/r` to resend everything unacked with
the same UUIDs (which must not produce duplicate replies).

---

## How it fits together

```
iPhone ──one WebSocket──▶ relay ──▶ AI A adapter (Claude)
       ──REST for the rest──▶      ──▶ AI B adapter (OpenAI)
                                   └──▶ SQLite (messages, diary, todos, health)
```

**One socket, three channels.** Every message carries `channel` (`ai_a` /
`ai_b` / `group`), so there is no per-conversation networking code.

**Persist → ack → wake, in that order.** A phone that sends and immediately
loses signal never loses a message, and it can retry with the same UUID; the
relay dedupes on it. The app keeps an `outbox.json` of unacked messages and
flushes it on reconnect, plus a `chat-cache.json` so history reads offline.

**Four isolated AI contexts** — `ai_a:private`, `ai_a:group`, `ai_b:private`,
`ai_b:group`. Each gets its own serial queue, so two quick messages can't fire
overlapping requests or come back out of order, while AI A and AI B still think
in parallel in the group.

**The group can't loop.** A user turn wakes both AIs. An AI's reply only reaches
the other on an explicit `@mention`, and a reply that was itself triggered by an
AI carries `hop: 1` and is never forwarded again. An AI that has nothing to add
answers `__NO_REPLY__`, which is stored and broadcast nowhere.

**Scrolling up pages backwards.** The socket delivers the newest page on
connect, along with the cursor for the page before it; older ones come from
`GET /api/messages?cursor=…`. The cursor is `(time, rowid)` rather than a bare
timestamp, because two AI replies routinely land in the same millisecond and a
timestamp-only cursor makes every sibling at a page boundary unreachable.
Loading is driven by scroll position rather than a sentinel's `onAppear`, which
fires once and then stalls because the spinner never leaves the screen.

**Two jobs run without anyone opening the app.** At `WHISPER_HOUR` the relay
writes the day's whisper so it's already on Home when you look, and it keeps a
dated SQLite backup under `data/backups/` (last `KEEP_BACKUPS`, default 14). An
erase takes its own safety copy first.

---

## Going beyond localhost

`127.0.0.1` on a real iPhone means the phone. For a device or a public entry
point, terminate TLS in front of the relay and switch the app to `wss://`:

```
iPhone → wss://your.domain → Caddy on a VPS → SSH reverse tunnel → 127.0.0.1:9191
```

```bash
ssh -N -T -R 127.0.0.1:18080:127.0.0.1:9191 you@your-vps
```

Caddy handles HTTPS and the WebSocket upgrade. **No AI key belongs in the
Caddyfile** — the relay is still the only process that holds one.

This layout is single-user by design. Opening it to arbitrary signups needs more
than a domain: per-user identity and revocation, a `userId` on every row and
every broadcast, per-user AI contexts, rate limits and spend caps, and a privacy
policy with a data-deletion path.

---

## Layout

```
relay/
├── server.mjs          HTTP + WS transport, auth on both
├── relay.mjs           the engine: persist → ack → route
├── router.mjs          group routing table, hop limit, NO_REPLY
├── queue.mjs           one serial lane per channel+agent
├── store.mjs           node:sqlite, single writer
├── scheduler.mjs       daily whisper + rolling backups
├── protocol.mjs        the wire contract, shared with iOS
├── agents.mjs          one interface in front of both AIs
├── adapters/           claude · openai · echo
├── api/                home · messages · diary · todos · health
│                       · whisper · search · data
└── tools/              cli-client · seed-demo

ios/YourChat/
├── Models/             ChatMessage · DiaryEntry · HealthSnapshot · HomePayload
├── Services/           ChatService · APIClient · HealthService · RelayConfig
├── Theme/              Skin · ThemeStore · SkinSurfaces
└── Features/           Launch · Root · Home · Chats · Diary · Search · Settings
```

## Configuration worth knowing

| Env var | Default | What it does |
|---|---|---|
| `WHISPER_HOUR` | `7` | Hour of day the whisper is written without being asked |
| `KEEP_BACKUPS` | `14` | Dated backups retained under `data/backups/` |
| `AI_A_EFFORT` | `medium` | Claude's reasoning depth; `low` is cheaper and snappier |
| `HOME_LAT` / `HOME_LON` | — | Blank hides the weather line on Home |

## Requirements

Node 22.5+ (uses the built-in `node:sqlite` and `process.loadEnvFile`), Xcode 26
with the iOS 26 SDK, iOS 18+.

## License

[Apache-2.0](LICENSE).

The relay talks to Anthropic and OpenAI through their own SDKs; using it means
agreeing to their terms and paying for your own usage. No credentials, prompts,
or conversations from this repo's author are included — `relay/prompts/*.example.md`
and `relay/.env.example` are placeholders, and everything personal (names,
dates, personas) is configuration you supply at runtime.

---

This repo started as a hello-world; that original still lives in
[HELLO-MAC.md](HELLO-MAC.md).
