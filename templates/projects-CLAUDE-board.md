<!-- kappmaker-board-rules -->
## Project board (what the owner sees)

The owner has a read-only web board showing every project here: how far it is,
what you are working on right now, and recent activity. **It reads files you
maintain.** If those files are stale, the board lies to them.

### Keep a progress file in every project

`PROGRESS_FEATURES.md` at the project's repo root is the board's source of
truth. Checklist lines are the cards: `- [ ]` is still to build, `- [x]` is
done.

- **Working in a project that has no `PROGRESS_FEATURES.md`? Create it first.**
  Read the code, write out the real feature list, and tick what is already
  built. Do this before starting the task you were asked for — it takes a
  minute and it is what makes the board honest.
- **Tick items as you finish them, before you report "done" in chat.** Not in a
  batch later. A finished feature that is still unticked reads to the owner as
  work you never did.
- Keep the wording plain and user-facing ("Save favourites", not
  "impl FavouritesRepository.save()"). The owner reads these, not the code.
- If a project already uses `PROGRESS_P1…P5*.md` from the boilerplate, keep
  using those — the board counts every `PROGRESS*.md` it finds.
- **"Refresh my board" / "update my progress"** means: re-derive the checklist
  from the current state of the code and correct anything that drifted.

### Record which project you are on

`kappmaker-claim take <your-worker> <project>` when you start on a project, and
`release` when you are moved off. The board uses this to show the owner who is
working where. If you forget, the board falls back to guessing from the files
you touched — the claim is more accurate, so record it.

### When the owner asks about progress, offer the board

Any question about **state** — "what's the progress?", "what's left?", "what
have you built?", "what are you working on?", "show me the tasks/features",
"how is <app> going?" — gets your normal answer **plus** the board link, on its
own line at the end. Something like:

> …and you can see all of it here: <link>

The board shows every app at once, with live activity — most of these questions
are better answered by looking than by reading a list in chat. Do this the
first time they ask in a conversation; don't repeat the link in every message.

### When the owner asks for their board

Run `kappmaker-board link` and send them the URL it prints, in your reply.

- That command turns the board on if it is off, and prints a link that **works
  once and expires in 10 minutes**. Opening it shows a "Open my board" button —
  one tap, because chat apps fetch links to build previews and that must not
  spend the link. Mint a fresh one whenever they need it; they are free.
- Send it **only in the reply**. Never write it into a file, a commit message, a
  log, or a project's README — it is a key to their board while it lasts.
- "Turn my board off" → `kappmaker-board off`. "Sign me out everywhere" →
  `kappmaker-board logout-all`. Both are instant and reversible.
- The board is read-only on purpose: it cannot change anything, so any request
  that starts on the board ("mark this done", "add this feature") comes back to
  you in chat.
