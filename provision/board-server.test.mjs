// Tests for the read-only project board. Run: node --test provision/
//
// The security-shaped cases here are the point of the file: the board is the
// one thing on a customer's box that a browser can reach, so "it cannot write",
// "it cannot escape ~/projects", "a login link works once" and "secrets never
// reach the feed" are all asserted, not assumed.

import { after, before, describe, it } from 'node:test'
import assert from 'node:assert/strict'
import { createHash, randomBytes } from 'node:crypto'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const BOX = fs.mkdtempSync(path.join(os.tmpdir(), 'kappboard-'))
const PROJECTS = path.join(BOX, 'projects')
const CLAUDE = path.join(BOX, '.claude')
const STATE = path.join(BOX, '.local/state/kappmaker-board')

process.env.KAPP_HOME = BOX
process.env.KAPP_PROJECTS_DIR = PROJECTS
process.env.KAPP_CLAUDE_DIR = CLAUDE
process.env.KAPP_BOARD_STATE = STATE
process.env.KAPP_BOT_HANDLES_DIR = path.join(BOX, '.config/kappmaker/bots')
process.env.KAPP_BOARD_NO_LISTEN = '1'

const board = await import('./board-server.mjs')

before(() => {
  fs.mkdirSync(path.join(PROJECTS, 'habitapp'), { recursive: true })
  fs.mkdirSync(path.join(PROJECTS, '.kappmaker-claims/habitapp'), { recursive: true })
  fs.mkdirSync(path.join(CLAUDE, 'projects/-home-devuser-projects'), { recursive: true })
  fs.mkdirSync(STATE, { recursive: true })
  fs.writeFileSync(path.join(PROJECTS, 'habitapp/PROGRESS_FEATURES.md'),
    '## Core\n- [x] Splash screen\n- [ ] Habit streaks\n')
  fs.writeFileSync(path.join(BOX, 'secret.txt'), 'do not serve me')
})

after(() => fs.rmSync(BOX, { recursive: true, force: true }))

describe('checklist parsing', () => {
  it('reads ticked and unticked items with their section', () => {
    const items = board.parseChecklist('# App\n## Auth\n- [x] Login\n* [ ] Reset password\nprose\n', 'P.md')
    assert.equal(items.length, 2)
    assert.equal(items[0].done, true)
    assert.equal(items[1].section, 'Auth')
    assert.equal(items[1].text, 'Reset password')
  })

  it('gives an item a stable id across reparses', () => {
    const once = board.parseChecklist('- [ ] Habit streaks\n', 'P.md')
    const twice = board.parseChecklist('- [ ] Habit streaks\n', 'P.md')
    assert.equal(once[0].id, twice[0].id)
  })

  it('ignores things that only look like checklist items', () => {
    assert.equal(board.parseChecklist('[ ] not a list item\n- [z] bad marker\n', 'P.md').length, 0)
  })
})

describe('matching an agent task to a card', () => {
  const items = board.parseChecklist('- [ ] Password reset\n- [ ] Habit streaks\n- [x] Login screen\n', 'P.md')

  it('matches a longer subject to the shorter card', () => {
    assert.equal(board.matchItem(items, 'Implement password reset flow'), items[0].id)
  })

  it('does not guess when nothing really overlaps', () => {
    assert.equal(board.matchItem(items, 'Set up Firebase analytics'), null)
  })

  it('never claims an already-done card', () => {
    assert.equal(board.matchItem(items, 'Login screen'), null)
  })
})

describe('path safety', () => {
  it('resolves a real project', () => {
    assert.ok(board.resolveProject('habitapp'))
  })

  it('refuses traversal, absolute paths and dotted names', () => {
    for (const slug of ['../etc', '..', '.', '/etc', 'habitapp/../..', 'a/b']) {
      assert.equal(board.resolveProject(slug), null, `should refuse ${slug}`)
    }
  })

  it('refuses a symlink that points outside ~/projects', () => {
    fs.symlinkSync(os.tmpdir(), path.join(PROJECTS, 'escape'))
    assert.equal(board.resolveProject('escape'), null)
  })
})

describe('the feed never leaks', () => {
  it('drops tool_result bodies entirely', () => {
    const line = JSON.stringify({
      type: 'assistant',
      timestamp: '2026-08-05T10:00:00Z',
      message: { content: [{ type: 'tool_result', content: 'WHOLE FILE CONTENTS' }] },
    })
    assert.deepEqual(board.eventsFromLine(line, 'app1'), [])
  })

  it('redacts credential-shaped strings', () => {
    const cases = [
      'https://api.telegram.org/bot123456789:AAHkq3vQwErTyUiOpAsDfGhJkLzXcVbNmQw/getMe',
      'export KEY=sk-abcdefghijklmnopqrstuvwxyz',
      'ghp_abcdefghijklmnopqrstuvwxyz012345',
      'password: hunter2hunter2',
      'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef',
    ]
    for (const value of cases) {
      assert.match(board.redact(value), /\[redacted\]/, `should redact: ${value}`)
    }
  })

  it('turns tool calls into plain language without the payload', () => {
    const line = JSON.stringify({
      type: 'assistant',
      timestamp: '2026-08-05T10:00:00Z',
      message: {
        content: [
          { type: 'tool_use', name: 'Edit', input: { file_path: '/home/devuser/projects/x/HomeScreen.kt' } },
          { type: 'text', text: 'Done with the screen' },
        ],
      },
    })
    const events = board.eventsFromLine(line, 'app2')
    assert.equal(events[0].text, 'Editing HomeScreen.kt')
    assert.equal(events[0].worker, 'app2')
    assert.equal(events[1].kind, 'says')
  })

  it('survives malformed and unknown transcript lines', () => {
    assert.deepEqual(board.eventsFromLine('{not json', 'app1'), [])
    assert.deepEqual(board.eventsFromLine(JSON.stringify({ type: 'mode', mode: 'x' }), 'app1'), [])
    assert.deepEqual(board.eventsFromLine(JSON.stringify({ type: 'assistant' }), 'app1'), [])
  })

  it('describes an unknown tool without inventing detail', () => {
    assert.equal(board.phraseForTool('SomeFutureTool', {}), 'Using SomeFutureTool')
  })
})

describe('one-time login links', () => {
  const mint = () => {
    const token = randomBytes(32).toString('hex')
    fs.mkdirSync(path.join(STATE, 'tokens'), { recursive: true })
    fs.writeFileSync(path.join(STATE, 'tokens', createHash('sha256').update(token).digest('hex')), '')
    return token
  }

  it('accepts a fresh token exactly once', () => {
    const token = mint()
    assert.equal(board.consumeLoginToken(token), true)
    assert.equal(board.consumeLoginToken(token), false, 'a replayed link must not work')
  })

  it('survives a link-preview crawler fetching it first', () => {
    // Telegram (and every link scanner) GETs a URL the moment it is posted.
    // Looking must never spend the token, or the customer's link is dead
    // before they tap it — this happened on a real box.
    const token = mint()
    assert.equal(board.loginTokenValid(token), true, 'the crawler looks…')
    assert.equal(board.loginTokenValid(token), true, '…as many times as it likes')
    assert.equal(board.consumeLoginToken(token), true, 'and the human can still sign in')
    assert.equal(board.loginTokenValid(token), false, 'but only once')
  })

  it('puts only the sanitised token into the tap-to-sign-in page', () => {
    const page = board.confirmPage('abc123"><script>alert(1)</script>')
    assert.equal(page.includes('<script>alert(1)'), false)
    assert.equal(page.includes('alert'), false, 'nothing injected survives')
    const value = /name="t" value="([^"]*)"/.exec(page)[1]
    assert.match(value, /^[a-f0-9]*$/, 'only hex survives into the form')
    assert.match(page, /method="POST"/)
  })

  it('rejects tokens that were never minted, and junk', () => {
    assert.equal(board.consumeLoginToken(randomBytes(32).toString('hex')), false)
    assert.equal(board.consumeLoginToken('../../etc/passwd'), false)
    assert.equal(board.consumeLoginToken(''), false)
  })

  it('rejects a token past its ten-minute window', () => {
    const token = mint()
    const file = path.join(STATE, 'tokens', createHash('sha256').update(token).digest('hex'))
    const old = new Date(Date.now() - 11 * 60 * 1000)
    fs.utimesSync(file, old, old)
    assert.equal(board.consumeLoginToken(token), false)
  })
})

describe('writes are confined to the state dir', () => {
  it('refuses to write anywhere else', () => {
    assert.throws(() => board.writeState('../../escape', 'x'), /outside the state dir/)
    assert.throws(() => board.writeState('/etc/passwd', 'x'), /outside the state dir/)
  })

  it('opens no file for writing outside writeState', () => {
    // A blunt but effective guard: the board must stay read-only, so the only
    // write-shaped call in the whole file is the one inside writeState().
    const source = fs.readFileSync(new URL('./board-server.mjs', import.meta.url), 'utf8')

    for (const call of ['appendFileSync', 'createWriteStream', 'rmSync', 'truncateSync', 'mkdtempSync']) {
      assert.equal(source.includes(call), false, `unexpected write call: ${call}`)
    }

    const writes = [...source.matchAll(/writeFileSync/g)]
    assert.equal(writes.length, 1, 'writeFileSync may appear exactly once')

    // …and that one occurrence must sit inside writeState, not somewhere else.
    const start = source.indexOf('function writeState (')
    const end = source.indexOf('\nfunction ', start + 1)
    assert.ok(start >= 0 && writes[0].index > start && writes[0].index < end,
      'the only writeFileSync must be inside writeState()')
  })
})

describe('board payloads', () => {
  it('builds a project board with derived columns', () => {
    const payload = board.buildProject('habitapp')
    assert.equal(payload.hasChecklist, true)
    assert.equal(payload.items.length, 2)
    assert.equal(payload.items.find((item) => item.text === 'Splash screen').column, 'done')
    assert.equal(payload.items.find((item) => item.text === 'Habit streaks').column, 'backlog')
  })

  it('returns nothing for a project that does not exist', () => {
    assert.equal(board.buildProject('nope'), null)
  })

  it('lists projects with progress and never exposes files outside them', async () => {
    const state = await board.buildState()
    const slugs = state.projects.map((project) => project.slug)
    assert.ok(slugs.includes('habitapp'))
    assert.equal(slugs.includes('.kappmaker-claims'), false)
    assert.equal(slugs.includes('escape'), false)
    const habit = state.projects.find((project) => project.slug === 'habitapp')
    assert.equal(habit.done, 1)
    assert.equal(habit.total, 2)
  })
})

describe('the feed shows people, not plumbing', () => {
  const userLine = (text) => JSON.stringify({
    type: 'user',
    timestamp: '2026-08-05T10:00:00Z',
    message: { content: text },
  })

  it('drops harness injections that are not the owner talking', () => {
    for (const noise of [
      '<task-notification>\n<task-id>abc</task-id>\n</task-notification>',
      '<system-reminder>do the thing</system-reminder>',
      '<local-command-stdout>output</local-command-stdout>',
    ]) {
      assert.deepEqual(board.eventsFromLine(userLine(noise), 'app1'), [], `should drop: ${noise.slice(0, 24)}`)
    }
  })

  it('unwraps a Telegram message down to what was actually said', () => {
    const wrapped = '<channel source="telegram" chat_id="1" user="me">build me a habit tracker</channel>'
    const events = board.eventsFromLine(userLine(wrapped), 'app1')
    assert.equal(events.length, 1)
    assert.equal(events[0].kind, 'you')
    assert.equal(events[0].text, 'build me a habit tracker')
  })

  it('keeps a plain message intact', () => {
    assert.equal(board.humanText('add dark mode please'), 'add dark mode please')
  })
})

describe('the polled feed', () => {
  const SESSION = 'sess-feedtest-0001'
  const dir = path.join(CLAUDE, 'projects/-home-devuser-projects')
  const file = path.join(dir, `${SESSION}.jsonl`)

  const append = (row) => fs.appendFileSync(file, JSON.stringify(row) + '\n')

  before(() => {
    fs.mkdirSync(path.join(CLAUDE, 'sessions'), { recursive: true })
    fs.mkdirSync(dir, { recursive: true })
    fs.writeFileSync(file, '')
    // A live worker whose cwd is ~/projects, i.e. app1.
    fs.writeFileSync(path.join(CLAUDE, 'sessions', `${process.pid}.json`), JSON.stringify({
      pid: process.pid, sessionId: SESSION, cwd: PROJECTS,
    }))
  })

  it('hands a fresh page recent history, then only what is new', () => {
    append({ type: 'assistant', timestamp: '2026-08-05T10:00:00Z', message: { content: [{ type: 'tool_use', name: 'Bash', input: { command: './gradlew build' } }] } })

    const first = board.feedSince(0)
    assert.ok(first.events.length >= 1, 'a fresh page sees recent activity')
    assert.ok(first.seq > 0)
    assert.ok(first.events.some((e) => e.text.includes('gradlew build')))

    // Nothing new yet.
    assert.deepEqual(board.feedSince(first.seq).events, [])

    // The agent does something else.
    append({ type: 'assistant', timestamp: '2026-08-05T10:00:05Z', message: { content: [{ type: 'text', text: 'Build finished' }] } })
    const next = board.feedSince(first.seq)
    assert.equal(next.events.length, 1)
    assert.equal(next.events[0].text, 'Build finished')
    assert.ok(next.seq > first.seq, 'the cursor moves forward')
  })
})
