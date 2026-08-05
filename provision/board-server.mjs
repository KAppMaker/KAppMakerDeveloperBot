#!/usr/bin/env node
// KAppMaker AI — read-only project board.
//
// Serves the customer a window into their own box: which projects exist, how
// far each one is, which bot is on what, and a live feed of what Claude Code is
// doing right now. Installed by bootstrap.sh as ~/bin/board-server.mjs and run
// by kappmaker-board.service.
//
// DESIGN RULES (each one is load-bearing — see docs/BOARD.md):
//
//   1. READ-ONLY. Nothing here ever writes to ~/projects or ~/.claude. The only
//      writable location is STATE_DIR (sessions + last-seen), and every write
//      goes through writeState() so that stays auditable. A board that could
//      write would be a path for an attacker to plant text that the always-on
//      agent later reads and acts on — the agent runs with
//      --dangerously-skip-permissions, so that would be remote code execution
//      by proxy. It cannot write, so that path does not exist.
//
//   2. LOOPBACK ONLY. We bind 127.0.0.1. Reachability comes from an OUTBOUND
//      cloudflared tunnel (kappmaker-board-tunnel.service), so no inbound port
//      is ever opened on the box — a port scan still finds only SSH.
//
//   3. THE BOT IS THE LOGIN. `kappmaker-board link` mints a single-use token
//      with a short TTL and the customer's own Telegram bot delivers it. No
//      password, and no URL that is permanently a credential.
//
//   4. NOTHING SENSITIVE LEAVES. tool_result bodies are never emitted (they
//      carry whole files and command output) and everything that IS emitted
//      goes through redact(). systemd additionally hides ~/.claude/.credentials
//      .json and ~/.claude/channels/ from this process entirely.
//
// Zero npm dependencies on purpose: node stdlib only, so there is nothing to
// install, audit or keep patched on a customer's machine.

import { createServer } from 'node:http'
import { createHash, randomBytes, timingSafeEqual } from 'node:crypto'
import { execFile } from 'node:child_process'
import { fileURLToPath } from 'node:url'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const HOME = process.env.KAPP_HOME || os.homedir()
const PROJECTS_DIR = process.env.KAPP_PROJECTS_DIR || path.join(HOME, 'projects')
const CLAUDE_DIR = process.env.KAPP_CLAUDE_DIR || path.join(HOME, '.claude')
const STATE_DIR = process.env.KAPP_BOARD_STATE || path.join(HOME, '.local/state/kappmaker-board')
const BOT_HANDLES_DIR = process.env.KAPP_BOT_HANDLES_DIR || path.join(HOME, '.config/kappmaker/bots')
const UI_FILE = process.env.KAPP_BOARD_UI
  || path.join(path.dirname(fileURLToPath(import.meta.url)), 'board.html')

const PORT = Number(process.env.KAPP_BOARD_PORT || 7788)
const BIND = '127.0.0.1'

const SESSION_COOKIE = 'kb_session'
const SESSION_TTL_MS = 30 * 24 * 60 * 60 * 1000   // 30 days
const TOKEN_TTL_MS = 10 * 60 * 1000               // 10 minutes — one-time links
const CLAIMS_DIRNAME = '.kappmaker-claims'
const PROJECT_SLUG_RE = /^[A-Za-z0-9._-]{1,64}$/
const PROGRESS_FILE_RE = /^PROGRESS.*\.md$/i
const CHECK_ITEM_RE = /^\s*[-*]\s+\[([ xX])\]\s+(.+?)\s*$/
const DEFAULT_PROGRESS_FILE = 'PROGRESS_FEATURES.md'

const GIT_CACHE_MS = 10_000
const GIT_TIMEOUT_MS = 4_000
const GIT_MAX_CONCURRENT = 2
const MAX_SSE_CLIENTS = 2
const SSE_MAX_MS = 30 * 60 * 1000                 // drop the stream after 30 min
const TAIL_WINDOW = 32 * 1024                     // transcripts run to tens of MB
// Inference reads further back than the live tail: "which project is this bot
// on" can be several turns old, while the feed only ever wants what just
// happened. Still bounded, still cached.
const INFER_WINDOW = 512 * 1024
const STREAM_POLL_MS = 1_000

// ---------------------------------------------------------------- utilities

/** The ONLY function in this file allowed to write. Refuses to escape STATE_DIR. */
function writeState (name, data) {
  const target = path.join(STATE_DIR, name)
  if (path.dirname(path.resolve(target)) !== path.resolve(STATE_DIR)) {
    throw new Error('writeState: refusing to write outside the state dir')
  }
  fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 })
  const tmp = `${target}.${process.pid}.tmp`
  fs.writeFileSync(tmp, data, { mode: 0o600 })
  fs.renameSync(tmp, target)
}

function readFileSafe (file, encoding = 'utf8') {
  try {
    return fs.readFileSync(file, encoding)
  } catch {
    return null
  }
}

function readJsonSafe (file) {
  const raw = readFileSafe(file)
  if (raw === null) return null
  try {
    return JSON.parse(raw)
  } catch {
    return null
  }
}

function listDirSafe (dir, withTypes = true) {
  try {
    return fs.readdirSync(dir, { withFileTypes: withTypes })
  } catch {
    return []
  }
}

function sha256 (value) {
  return createHash('sha256').update(value).digest('hex')
}

function shortId (value) {
  return createHash('sha1').update(value).digest('hex').slice(0, 8)
}

/**
 * Strip anything that looks like a credential before it leaves the box.
 * Defence in depth: this is the customer's own data behind their own login,
 * but a transcript can contain whatever the agent happened to echo.
 */
const REDACTIONS = [
  /-----BEGIN[^-]{0,40}-----[\s\S]*?-----END[^-]{0,40}-----/g,  // PEM keys
  /\bsk-[A-Za-z0-9_-]{16,}/g,                                   // API keys
  /\bgh[pousr]_[A-Za-z0-9]{20,}/g,                              // GitHub tokens
  // Telegram bot tokens. No leading \b on purpose: they are usually written as
  // `bot<digits>:<secret>` in an API URL, and `t`→`1` is not a word boundary.
  /\d{6,}:[A-Za-z0-9_-]{30,}/g,
  /\bey[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]{10,}\.[A-Za-z0-9_-]+/g, // JWTs
  /\b(?:authorization|api[_-]?key|access[_-]?token|secret|password)\b\s*[:=]\s*\S+/gi,
  /\b[A-Fa-f0-9]{32,}\b/g,                                      // bare hex secrets
]

function redact (text) {
  if (typeof text !== 'string' || text === '') return ''
  let out = text
  for (const re of REDACTIONS) out = out.replace(re, '[redacted]')
  return out
}

function clip (text, max) {
  const value = String(text ?? '')
  return value.length > max ? `${value.slice(0, max - 1)}…` : value
}

// ------------------------------------------------------------ rate limiting

const buckets = new Map()

/**
 * Token bucket. Everything arrives from the tunnel as 127.0.0.1, so we key on
 * cloudflared's forwarded client IP where present and always keep a global
 * ceiling as the real backstop.
 */
function allowRequest (key, cost = 1, capacity = 60, refillPerSec = 1) {
  const now = Date.now()
  let bucket = buckets.get(key)
  if (!bucket) {
    bucket = { tokens: capacity, at: now }
    buckets.set(key, bucket)
  }
  bucket.tokens = Math.min(capacity, bucket.tokens + ((now - bucket.at) / 1000) * refillPerSec)
  bucket.at = now
  if (bucket.tokens < cost) return false
  bucket.tokens -= cost
  return true
}

setInterval(() => {
  const cutoff = Date.now() - 10 * 60 * 1000
  for (const [key, bucket] of buckets) if (bucket.at < cutoff) buckets.delete(key)
}, 60_000).unref()

function clientKey (req) {
  const forwarded = req.headers['cf-connecting-ip']
  return typeof forwarded === 'string' && forwarded.length <= 45 ? forwarded : 'local'
}

// ------------------------------------------------------------------ sessions

function loadSessions () {
  return readJsonSafe(path.join(STATE_DIR, 'sessions.json')) || {}
}

function saveSessions (sessions) {
  writeState('sessions.json', JSON.stringify(sessions))
}

function pruneSessions (sessions) {
  const now = Date.now()
  let changed = false
  for (const [hash, entry] of Object.entries(sessions)) {
    if (!entry || typeof entry.expires !== 'number' || entry.expires < now) {
      delete sessions[hash]
      changed = true
    }
  }
  return changed
}

function createSession () {
  const id = randomBytes(32).toString('hex')
  const sessions = loadSessions()
  pruneSessions(sessions)
  sessions[sha256(id)] = { created: Date.now(), expires: Date.now() + SESSION_TTL_MS }
  saveSessions(sessions)
  return id
}

function sessionIdFrom (req) {
  const header = req.headers.cookie
  if (!header) return null
  for (const part of header.split(';')) {
    const [name, ...rest] = part.trim().split('=')
    if (name === SESSION_COOKIE) return rest.join('=')
  }
  return null
}

function isAuthenticated (req) {
  const id = sessionIdFrom(req)
  if (!id || !/^[a-f0-9]{64}$/.test(id)) return false
  const sessions = loadSessions()
  const entry = sessions[sha256(id)]
  return Boolean(entry && typeof entry.expires === 'number' && entry.expires > Date.now())
}

function dropSession (req) {
  const id = sessionIdFrom(req)
  if (!id) return
  const sessions = loadSessions()
  delete sessions[sha256(id)]
  saveSessions(sessions)
}

/**
 * Consume a one-time login token. `kappmaker-board link` created the file named
 * after the token's SHA-256; renaming it is the atomic claim, so a replayed
 * link loses the race and gets nothing. TTL comes from the file's mtime.
 */
function consumeLoginToken (token) {
  if (typeof token !== 'string' || !/^[a-f0-9]{64}$/.test(token)) return false
  const tokensDir = path.join(STATE_DIR, 'tokens')
  const file = path.join(tokensDir, sha256(token))
  let stat
  try {
    stat = fs.statSync(file)
  } catch {
    return false
  }
  // Constant-time on the hash we just derived — the filename lookup already
  // leaks nothing, but keep the comparison shape honest.
  const expected = Buffer.from(sha256(token))
  const actual = Buffer.from(path.basename(file))
  if (expected.length !== actual.length || !timingSafeEqual(expected, actual)) return false

  try {
    fs.renameSync(file, `${file}.used.${process.pid}`)
  } catch {
    return false   // someone else claimed it first
  }
  try {
    fs.unlinkSync(`${file}.used.${process.pid}`)
  } catch { /* best effort */ }

  return Date.now() - stat.mtimeMs <= TOKEN_TTL_MS
}

let lastSeenWrittenAt = 0
function touchLastSeen () {
  const now = Date.now()
  if (now - lastSeenWrittenAt < 60_000) return
  lastSeenWrittenAt = now
  try {
    writeState('last-seen', `${Math.floor(now / 1000)}\n`)
  } catch { /* never fail a request over this */ }
}

// ----------------------------------------------------------------- projects

function projectsRoot () {
  try {
    return fs.realpathSync(PROJECTS_DIR)
  } catch {
    return PROJECTS_DIR
  }
}

/** Resolve a slug to a real directory inside ~/projects, or null. */
function resolveProject (slug) {
  if (!PROJECT_SLUG_RE.test(slug) || slug === '.' || slug === '..') return null
  const root = projectsRoot()
  let real
  try {
    real = fs.realpathSync(path.join(root, slug))
  } catch {
    return null
  }
  if (real !== root && !real.startsWith(root + path.sep)) return null
  try {
    if (!fs.statSync(real).isDirectory()) return null
  } catch {
    return null
  }
  return real
}

function listProjectSlugs () {
  return listDirSafe(PROJECTS_DIR)
    .filter((entry) => entry.isDirectory() && !entry.name.startsWith('.'))
    .map((entry) => entry.name)
    .filter((name) => PROJECT_SLUG_RE.test(name))
    .sort((a, b) => a.localeCompare(b))
}

function progressFiles (dir) {
  return listDirSafe(dir)
    .filter((entry) => entry.isFile() && PROGRESS_FILE_RE.test(entry.name))
    .map((entry) => entry.name)
    .sort((a, b) => {
      if (a === DEFAULT_PROGRESS_FILE) return -1
      if (b === DEFAULT_PROGRESS_FILE) return 1
      return a.localeCompare(b)
    })
}

/**
 * Parse a PROGRESS_*.md checklist. `- [ ]` is backlog, `- [x]` is done; the
 * nearest heading above becomes the item's section. Deliberately the same
 * convention the kappmaker boilerplate already writes — the board asks the
 * agent for no new discipline and no new file format.
 */
function parseChecklist (text, file) {
  const items = []
  let section = ''
  let index = 0
  for (const line of String(text).split('\n')) {
    const heading = /^#{1,6}\s+(.*\S)\s*$/.exec(line)
    if (heading) {
      section = clip(heading[1], 80)
      continue
    }
    const match = CHECK_ITEM_RE.exec(line)
    if (!match) continue
    const done = match[1].toLowerCase() === 'x'
    const label = clip(match[2].replace(/\s+/g, ' '), 400)
    items.push({
      id: shortId(`${file}:${index}:${label}`),
      text: label,
      section,
      done,
    })
    index += 1
  }
  return items
}

function readProgress (dir, file) {
  const target = path.join(dir, file)
  if (path.dirname(path.resolve(target)) !== path.resolve(dir)) return []
  if (!PROGRESS_FILE_RE.test(path.basename(target))) return []
  const text = readFileSafe(target)
  return text === null ? [] : parseChecklist(text, file)
}

function progressTotals (dir) {
  let done = 0
  let total = 0
  for (const file of progressFiles(dir)) {
    for (const item of readProgress(dir, file)) {
      total += 1
      if (item.done) done += 1
    }
  }
  return { done, total }
}

// --------------------------------------------------------------------- git

const gitCache = new Map()
let gitInFlight = 0
const gitQueue = []

function runGit (dir, args) {
  return new Promise((resolve) => {
    const start = () => {
      gitInFlight += 1
      execFile('git', ['--no-pager', '-C', dir, ...args], {
        timeout: GIT_TIMEOUT_MS,
        maxBuffer: 256 * 1024,
        env: { PATH: process.env.PATH || '/usr/bin:/bin', HOME, GIT_TERMINAL_PROMPT: '0' },
      }, (error, stdout) => {
        gitInFlight -= 1
        const next = gitQueue.shift()
        if (next) next()
        resolve(error ? null : String(stdout))
      })
    }
    if (gitInFlight >= GIT_MAX_CONCURRENT) gitQueue.push(start)
    else start()
  })
}

/** Last commit + dirty-file count, cached so nobody can fork-bomb a 4 GB box. */
async function gitActivity (dir) {
  const cached = gitCache.get(dir)
  if (cached && Date.now() - cached.at < GIT_CACHE_MS) return cached.value

  let value = { isRepo: false, lastCommit: null, dirty: 0 }
  const log = await runGit(dir, ['log', '-1', '--format=%s%x1f%cI'])
  if (log !== null) {
    const [subject, at] = log.trim().split('\x1f')
    value = {
      isRepo: true,
      lastCommit: subject ? { subject: redact(clip(subject, 160)), at: at || null } : null,
      dirty: 0,
    }
    const status = await runGit(dir, ['status', '--porcelain'])
    if (status !== null) {
      value.dirty = status.split('\n').filter((line) => line.trim() !== '').length
    }
  }
  gitCache.set(dir, { at: Date.now(), value })
  return value
}

// -------------------------------------------------------------- live agents

/** `~/projects/.kappmaker-claims/<project>/owner` → which worker took it. */
function claims () {
  const out = new Map()
  const dir = path.join(PROJECTS_DIR, CLAIMS_DIRNAME)
  for (const entry of listDirSafe(dir)) {
    if (!entry.isDirectory()) continue
    const owner = (readFileSafe(path.join(dir, entry.name, 'owner')) || '').trim()
    const since = (readFileSafe(path.join(dir, entry.name, 'since')) || '').trim()
    if (owner) out.set(entry.name, { owner, since: since || null })
  }
  return out
}

function workerFromCwd (cwd) {
  if (!cwd) return null
  const normalized = path.resolve(cwd)
  if (normalized === path.resolve(PROJECTS_DIR)) return 'app1'
  const match = /(?:^|\/)workspaces\/(app[1-9][0-9]?)\/?$/.exec(normalized)
  return match ? match[1] : null
}

/**
 * Is that session's process still around? `kill(pid, 0)` sends no signal and
 * works everywhere (EPERM means it exists but isn't ours, which still counts).
 */
function processAlive (pid) {
  if (!Number.isInteger(pid) || pid <= 0) return false
  try {
    process.kill(pid, 0)
    return true
  } catch (error) {
    return error && error.code === 'EPERM'
  }
}

/**
 * Claude Code's own live state: ~/.claude/sessions/<pid>.json says which
 * session is running where, and ~/.claude/tasks/<sessionId>/*.json holds that
 * session's task list. Nothing here is written by us — it exists for free.
 */
function liveWorkers () {
  const out = []
  for (const entry of listDirSafe(path.join(CLAUDE_DIR, 'sessions'))) {
    if (!entry.isFile() || !entry.name.endsWith('.json')) continue
    const info = readJsonSafe(path.join(CLAUDE_DIR, 'sessions', entry.name))
    if (!info || typeof info.sessionId !== 'string') continue

    const worker = workerFromCwd(info.cwd)
    if (!worker) continue
    if (info.pid && !processAlive(Number(info.pid))) continue

    out.push({
      worker,
      sessionId: info.sessionId,
      cwd: info.cwd || null,
      startedAt: typeof info.startedAt === 'number' ? info.startedAt : null,
      task: currentTask(info.sessionId),
    })
  }
  return out.sort((a, b) => a.worker.localeCompare(b.worker))
}

function currentTask (sessionId) {
  if (!/^[A-Za-z0-9-]{8,64}$/.test(sessionId)) return null
  const dir = path.join(CLAUDE_DIR, 'tasks', sessionId)
  const tasks = []
  for (const entry of listDirSafe(dir)) {
    if (!entry.isFile() || !entry.name.endsWith('.json')) continue
    const task = readJsonSafe(path.join(dir, entry.name))
    if (task && typeof task.subject === 'string') tasks.push(task)
  }
  if (tasks.length === 0) return null
  const active = tasks.find((task) => task.status === 'in_progress')
  const pending = tasks.filter((task) => task.status === 'pending').length
  const done = tasks.filter((task) => task.status === 'completed').length
  if (!active) return { subject: null, activeForm: null, pending, done, total: tasks.length }
  return {
    subject: redact(clip(active.subject, 200)),
    activeForm: redact(clip(active.activeForm || '', 200)) || null,
    pending,
    done,
    total: tasks.length,
  }
}

/**
 * Which project is this worker actually in?
 *
 * `kappmaker-claim` is ADVISORY by design — the agent is asked to record what
 * it picked up, but it can forget, and a claim can outlive a restart. So when
 * no claim matches we infer from evidence: the most recent project path the
 * worker touched, read from the tail of its own transcript. Without this, a
 * second bot quietly working on a second project would show as nobody home.
 */
const inferCache = new Map()

function inferProject (sessionId) {
  const cached = inferCache.get(sessionId)
  if (cached && Date.now() - cached.at < GIT_CACHE_MS) return cached.slug

  let slug = null
  const file = transcriptFor(sessionId)
  if (file) {
    try {
      const stat = fs.statSync(file)
      const length = Math.min(stat.size, INFER_WINDOW)
      const buffer = Buffer.alloc(length)
      const fd = fs.openSync(file, 'r')
      try {
        fs.readSync(fd, buffer, 0, length, Math.max(0, stat.size - length))
      } finally {
        fs.closeSync(fd)
      }
      const root = projectsRoot().replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
      const hits = [...buffer.toString('utf8').matchAll(new RegExp(`${root}/([A-Za-z0-9._-]{1,64})[/"\\\\]`, 'g'))]
      for (let i = hits.length - 1; i >= 0; i -= 1) {
        const candidate = hits[i][1]
        if (candidate.startsWith('.')) continue
        if (resolveProject(candidate)) { slug = candidate; break }
      }
    } catch { /* inference is best-effort by definition */ }
  }
  inferCache.set(sessionId, { at: Date.now(), slug })
  return slug
}

/**
 * Bot handles, so a card can offer "open this chat".
 *
 * Read from ~/.config/kappmaker/bots/<worker>, which the runners write after
 * their getMe call. Deliberately NOT from ~/.claude/channels/<...>/.env — that
 * file holds the Telegram bot TOKEN, and the board's systemd sandbox hides that
 * directory from this process entirely. A public @handle is all we ever touch.
 */
function botHandles () {
  const handles = new Map()
  for (const entry of listDirSafe(BOT_HANDLES_DIR)) {
    if (!entry.isFile() || !/^app[1-9][0-9]?$/.test(entry.name)) continue
    const handle = (readFileSafe(path.join(BOT_HANDLES_DIR, entry.name)) || '').trim().replace(/^@/, '')
    if (/^[A-Za-z0-9_]{5,32}$/.test(handle)) handles.set(entry.name, handle)
  }
  return handles
}

// ------------------------------------------------------------------ payload

/**
 * Bigger tiers run several always-on workers at once, each in its own chat on
 * its own app. Everything below is therefore per-worker: the board resolves
 * every live worker to a project (claim first, evidence second) and then hangs
 * each project card off that mapping, so two bots on two apps show as two
 * cards, both live.
 */
function workerProjects (workers, claimed) {
  const byWorker = new Map()
  for (const worker of workers) {
    const claim = [...claimed.entries()].find(([, entry]) => entry.owner === worker.worker)
    byWorker.set(worker.worker, {
      slug: claim ? claim[0] : inferProject(worker.sessionId),
      source: claim ? 'claim' : 'activity',
    })
  }
  return byWorker
}

async function buildState () {
  const claimed = claims()
  const workers = liveWorkers()
  const handles = botHandles()
  const placement = workerProjects(workers, claimed)

  const projects = []
  for (const slug of listProjectSlugs()) {
    const dir = resolveProject(slug)
    if (!dir) continue

    const files = progressFiles(dir)
    const totals = progressTotals(dir)
    const activity = await gitActivity(dir)

    // Every worker sitting on this project — normally one, but nothing stops
    // the owner pointing two bots at the same app.
    const here = workers.filter((worker) => placement.get(worker.worker)?.slug === slug)

    projects.push({
      slug,
      name: slug,
      hasChecklist: files.length > 0,
      progressFiles: files,
      done: totals.done,
      total: totals.total,
      git: activity,
      claim: claimed.get(slug) || null,
      bots: here.map((worker) => ({
        worker: worker.worker,
        handle: handles.get(worker.worker) || null,
        task: worker.task,
        via: placement.get(worker.worker)?.source || null,
      })),
    })
  }

  return {
    generatedAt: new Date().toISOString(),
    projects,
    workers: workers.map((worker) => ({
      worker: worker.worker,
      handle: handles.get(worker.worker) || null,
      task: worker.task,
      project: placement.get(worker.worker)?.slug || null,
      via: placement.get(worker.worker)?.source || null,
    })),
  }
}

function buildProject (slug) {
  const dir = resolveProject(slug)
  if (!dir) return null

  const files = progressFiles(dir)
  const requested = files.length > 0 ? files[0] : null
  const items = requested ? readProgress(dir, requested) : []

  const allClaims = claims()
  const workers = liveWorkers()
  const placement = workerProjects(workers, allClaims)
  const here = workers.filter((worker) => placement.get(worker.worker)?.slug === slug)
  const handles = botHandles()
  const task = here.map((worker) => worker.task).find((entry) => entry && entry.subject) || null

  // "Doing" is derived, never stored: an agent's own in-progress task, matched
  // back to a checklist line when the wording lines up. With several bots on
  // one app, every one of their tasks gets a chance to claim a card.
  const doingIds = new Set()
  for (const worker of here) {
    if (!worker.task || !worker.task.subject) continue
    const id = matchItem(items, worker.task.subject)
    if (id) doingIds.add(id)
  }

  return {
    slug,
    name: slug,
    progressFiles: files,
    file: requested,
    hasChecklist: files.length > 0,
    items: items.map((item) => ({
      ...item,
      column: item.done ? 'done' : (doingIds.has(item.id) ? 'doing' : 'backlog'),
    })),
    bots: here.map((worker) => ({
      worker: worker.worker,
      handle: handles.get(worker.worker) || null,
      task: worker.task,
      via: placement.get(worker.worker)?.source || null,
    })),
    claim: allClaims.get(slug) || null,
    task,
  }
}

/**
 * Loose match between an agent's task subject and a checklist line, so "Doing"
 * can point at a real card. Scored against the SHORTER of the two word sets:
 * a subject like "Implement password reset flow" should still find the item
 * "Password reset". Needs two shared significant words, so short generic items
 * never get claimed by accident.
 */
function matchItem (items, subject) {
  const normalize = (value) => value.toLowerCase().replace(/[^a-z0-9 ]+/g, ' ').replace(/\s+/g, ' ').trim()
  const significant = (value) => new Set(value.split(' ').filter((word) => word.length > 3))

  const target = normalize(subject)
  if (target.length < 4) return null
  const targetWords = significant(target)

  let best = null
  let bestScore = 0
  for (const item of items) {
    if (item.done) continue
    const candidate = normalize(item.text)
    if (candidate.length < 4) continue
    if (candidate === target) return item.id

    const candidateWords = significant(candidate)
    if (candidateWords.size === 0 || targetWords.size === 0) continue
    const shared = [...targetWords].filter((word) => candidateWords.has(word)).length
    if (shared < 2) continue

    const score = shared / Math.min(targetWords.size, candidateWords.size)
    if (score > bestScore) {
      bestScore = score
      best = item.id
    }
  }
  return bestScore >= 0.6 ? best : null
}

// ------------------------------------------------------------- live stream

/**
 * Find a session's transcript by scanning ~/.claude/projects/<encoded-cwd>/.
 * We scan rather than re-implement Claude Code's directory encoding, so a
 * change in that encoding cannot silently break the feed.
 */
function transcriptFor (sessionId) {
  if (!/^[A-Za-z0-9-]{8,64}$/.test(sessionId)) return null
  const root = path.join(CLAUDE_DIR, 'projects')
  for (const entry of listDirSafe(root)) {
    if (!entry.isDirectory()) continue
    const candidate = path.join(root, entry.name, `${sessionId}.jsonl`)
    if (fs.existsSync(candidate)) return candidate
  }
  return null
}

const TOOL_PHRASES = {
  Edit: (input) => `Editing ${path.basename(input.file_path || input.path || 'a file')}`,
  MultiEdit: (input) => `Editing ${path.basename(input.file_path || 'a file')}`,
  Write: (input) => `Writing ${path.basename(input.file_path || 'a file')}`,
  NotebookEdit: (input) => `Editing ${path.basename(input.notebook_path || 'a notebook')}`,
  Read: (input) => `Reading ${path.basename(input.file_path || 'a file')}`,
  Bash: (input) => `Running ${clip(input.command || '', 90)}`,
  Grep: () => 'Searching the code',
  Glob: () => 'Looking for files',
  Task: () => 'Planning the next steps',
  TaskCreate: () => 'Updating its task list',
  TaskUpdate: () => 'Updating its task list',
  TodoWrite: () => 'Updating its task list',
  WebFetch: () => 'Reading something on the web',
  WebSearch: () => 'Searching the web',
}

function phraseForTool (name, input) {
  const safeInput = input && typeof input === 'object' ? input : {}
  if (typeof name === 'string' && name.startsWith('mcp__plugin_telegram')) return 'Replying on Telegram'
  const phrase = TOOL_PHRASES[name]
  try {
    return phrase ? phrase(safeInput) : `Using ${clip(name || 'a tool', 40)}`
  } catch {
    return `Using ${clip(name || 'a tool', 40)}`
  }
}

/**
 * Turn one transcript line into at most a few feed events. tool_result blocks
 * are deliberately dropped: they carry whole file contents and command output.
 */
function eventsFromLine (line, worker) {
  let record
  try {
    record = JSON.parse(line)
  } catch {
    return []
  }
  if (!record || typeof record !== 'object') return []

  const type = record.type
  if (type !== 'assistant' && type !== 'user') return []

  const message = record.message
  const content = message && message.content
  const at = typeof record.timestamp === 'string' ? record.timestamp : new Date().toISOString()
  const events = []

  if (typeof content === 'string') {
    const text = redact(clip(content.trim(), 240))
    if (text) events.push({ at, worker, kind: type === 'user' ? 'you' : 'says', text })
    return events
  }
  if (!Array.isArray(content)) return []

  for (const block of content) {
    if (!block || typeof block !== 'object') continue
    if (block.type === 'text' && typeof block.text === 'string') {
      const text = redact(clip(block.text.trim(), 240))
      if (text) events.push({ at, worker, kind: type === 'user' ? 'you' : 'says', text })
    } else if (block.type === 'tool_use' && type === 'assistant') {
      events.push({ at, worker, kind: 'tool', text: redact(phraseForTool(block.name, block.input)) })
    }
    // tool_result: intentionally ignored — never leaves the box.
  }
  return events
}

let sseClients = 0

function startStream (req, res) {
  if (sseClients >= MAX_SSE_CLIENTS) {
    res.writeHead(503, { 'Content-Type': 'text/plain' })
    res.end('too many live viewers')
    return
  }
  sseClients += 1

  res.writeHead(200, {
    ...securityHeaders(),
    'Content-Type': 'text/event-stream',
    'Cache-Control': 'no-store',
    Connection: 'keep-alive',
  })
  res.write('retry: 5000\n\n')

  const tails = new Map()

  const attach = () => {
    for (const worker of liveWorkers()) {
      if (tails.has(worker.worker)) continue
      const file = transcriptFor(worker.sessionId)
      if (!file) continue
      let size = 0
      try {
        size = fs.statSync(file).size
      } catch {
        continue
      }
      // Start one window back so the viewer sees context immediately.
      tails.set(worker.worker, { file, pos: Math.max(0, size - TAIL_WINDOW), carry: '', primed: false })
    }
  }

  const pump = () => {
    attach()
    for (const [worker, tail] of tails) {
      let stat
      try {
        stat = fs.statSync(tail.file)
      } catch {
        tails.delete(worker)
        continue
      }
      if (stat.size < tail.pos) tail.pos = 0          // rotated/truncated
      if (stat.size === tail.pos) continue

      const length = Math.min(stat.size - tail.pos, TAIL_WINDOW)
      const buffer = Buffer.alloc(length)
      let fd
      try {
        fd = fs.openSync(tail.file, 'r')
        fs.readSync(fd, buffer, 0, length, tail.pos)
      } catch {
        continue
      } finally {
        if (fd !== undefined) try { fs.closeSync(fd) } catch { /* ignore */ }
      }
      tail.pos += length

      const chunk = tail.carry + buffer.toString('utf8')
      const lines = chunk.split('\n')
      tail.carry = lines.pop() || ''                  // keep the partial line

      // The first window starts mid-file, so its first line is usually a
      // fragment — drop it rather than emit garbage.
      if (!tail.primed) {
        tail.primed = true
        lines.shift()
      }

      for (const line of lines) {
        if (line.trim() === '') continue
        for (const event of eventsFromLine(line, worker)) {
          res.write(`data: ${JSON.stringify(event)}\n\n`)
        }
      }
    }
  }

  const poll = setInterval(pump, STREAM_POLL_MS)
  const beat = setInterval(() => res.write(': ping\n\n'), 20_000)
  const stop = setTimeout(() => res.end(), SSE_MAX_MS)
  pump()

  const cleanup = () => {
    clearInterval(poll)
    clearInterval(beat)
    clearTimeout(stop)
    sseClients = Math.max(0, sseClients - 1)
  }
  req.on('close', cleanup)
  res.on('close', cleanup)
}

// -------------------------------------------------------------------- http

function securityHeaders () {
  return {
    'X-Content-Type-Options': 'nosniff',
    'X-Frame-Options': 'DENY',
    'Referrer-Policy': 'no-referrer',
    'Content-Security-Policy': [
      "default-src 'none'",
      "script-src 'unsafe-inline'",
      "style-src 'unsafe-inline'",
      "img-src 'self' data:",
      "connect-src 'self'",
      "base-uri 'none'",
      "form-action 'none'",
      "frame-ancestors 'none'",
    ].join('; '),
  }
}

function sendJson (res, status, payload) {
  const body = JSON.stringify(payload)
  res.writeHead(status, {
    ...securityHeaders(),
    'Content-Type': 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(body),
  })
  res.end(body)
}

function sendHtml (res, status, html, extraHeaders = {}) {
  res.writeHead(status, {
    ...securityHeaders(),
    'Content-Type': 'text/html; charset=utf-8',
    'Cache-Control': 'no-store',
    'Content-Length': Buffer.byteLength(html),
    ...extraHeaders,
  })
  res.end(html)
}

function notFound (res) {
  res.writeHead(404, { ...securityHeaders(), 'Content-Type': 'text/plain' })
  res.end('not found')
}

/**
 * The page a stranger sees. Deliberately says nothing about the box: no project
 * names, no hostname, no version — only how the owner gets in.
 */
const LOGIN_PAGE = `<!doctype html>
<html lang="en"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<meta name="robots" content="noindex,nofollow"><title>Project board</title>
<style>
:root{color-scheme:dark}
body{margin:0;min-height:100vh;display:grid;place-items:center;background:#0b0f0e;color:#e5e5e5;
font:16px/1.6 ui-sans-serif,system-ui,-apple-system,"Segoe UI",sans-serif;padding:24px}
.card{max-width:26rem;text-align:center;border:1px solid rgba(255,255,255,.1);
background:rgba(15,21,19,.6);border-radius:24px;padding:40px 32px}
h1{margin:0 0 12px;font-size:1.35rem}
p{margin:0;color:#a3a3a3}
.dot{display:inline-block;width:8px;height:8px;border-radius:99px;background:#10b981;margin-right:8px}
</style></head>
<body><div class="card">
<h1><span class="dot"></span>Project board</h1>
<p>Ask your app builder for your board link in Telegram &mdash; it sends you a
fresh one that works once.</p>
</div></body></html>`

function serveUi (res) {
  const html = readFileSafe(UI_FILE)
  if (html === null) {
    sendHtml(res, 500, '<!doctype html><meta charset="utf-8"><p>Board UI missing. Re-run kappmaker-board-install.</p>')
    return
  }
  sendHtml(res, 200, html)
}

async function handle (req, res) {
  const url = new URL(req.url || '/', 'http://board.local')
  const route = url.pathname.replace(/\/+$/, '') || '/'

  if (!allowRequest(clientKey(req))) {
    res.writeHead(429, { ...securityHeaders(), 'Content-Type': 'text/plain' })
    res.end('slow down')
    return
  }

  // Login: consume the one-time token minted by `kappmaker-board link`.
  if (route === '/login' && req.method === 'GET') {
    if (!allowRequest(`login:${clientKey(req)}`, 1, 10, 0.2)) {
      res.writeHead(429, { ...securityHeaders(), 'Content-Type': 'text/plain' })
      res.end('too many attempts')
      return
    }
    if (!consumeLoginToken(url.searchParams.get('t') || '')) {
      sendHtml(res, 401, LOGIN_PAGE)
      return
    }
    const id = createSession()
    res.writeHead(302, {
      ...securityHeaders(),
      Location: '/',
      'Set-Cookie': `${SESSION_COOKIE}=${id}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${SESSION_TTL_MS / 1000}`,
    })
    res.end()
    return
  }

  if (route === '/logout' && req.method === 'POST') {
    // Custom header + SameSite=Lax: a third-party page cannot forge this.
    if (req.headers['x-board-request'] !== '1') {
      sendJson(res, 400, { error: 'bad request' })
      return
    }
    dropSession(req)
    res.writeHead(204, {
      ...securityHeaders(),
      'Set-Cookie': `${SESSION_COOKIE}=; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=0`,
    })
    res.end()
    return
  }

  const authed = isAuthenticated(req)

  if (route === '/' && req.method === 'GET') {
    if (!authed) {
      sendHtml(res, 200, LOGIN_PAGE)
      return
    }
    touchLastSeen()
    serveUi(res)
    return
  }

  if (!route.startsWith('/api/')) {
    notFound(res)
    return
  }
  if (!authed) {
    sendJson(res, 401, { error: 'not signed in' })
    return
  }
  if (req.method !== 'GET') {
    sendJson(res, 405, { error: 'read-only' })
    return
  }
  touchLastSeen()

  if (route === '/api/state') {
    sendJson(res, 200, await buildState())
    return
  }
  if (route === '/api/stream') {
    startStream(req, res)
    return
  }

  const project = /^\/api\/projects\/([^/]+)$/.exec(route)
  if (project) {
    const payload = buildProject(decodeURIComponent(project[1]))
    if (!payload) {
      sendJson(res, 404, { error: 'no such project' })
      return
    }
    sendJson(res, 200, payload)
    return
  }

  notFound(res)
}

const server = createServer((req, res) => {
  handle(req, res).catch(() => {
    try {
      sendJson(res, 500, { error: 'board error' })
    } catch { /* response already gone */ }
  })
})

// Exported for the test suite; only listens when run as a service.
export {
  buildProject,
  buildState,
  consumeLoginToken,
  eventsFromLine,
  matchItem,
  parseChecklist,
  phraseForTool,
  redact,
  resolveProject,
  server,
  writeState,
}

if (process.env.KAPP_BOARD_NO_LISTEN !== '1') {
  fs.mkdirSync(STATE_DIR, { recursive: true, mode: 0o700 })
  server.listen(PORT, BIND, () => {
    process.stdout.write(`kappmaker-board: listening on http://${BIND}:${PORT}\n`)
  })
}
