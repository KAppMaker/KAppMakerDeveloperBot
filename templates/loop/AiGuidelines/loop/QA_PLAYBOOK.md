# QA playbook — correctness, edge states & build safety

The shared reference for the self-improve loop's quality lens — used by the `orchestrator` at
**build time** and the `qa-engineer` at **review time**. It is the **correctness lens**: what
"it actually works" means for a Compose Multiplatform app, which failure modes break trust fastest,
and how to judge whether a change is safe to ship. The app's own `AiGuidelines/tech/*.md`
(`coroutines.md`, `repository.md`, `domain.md`, `presentation_layer.md`) hold *this app's* specific
conventions — read those for the architecture decisions; read this for the principles, the concrete
Kotlin/Compose/KMP checks, the must-block checklist, and the review rubric.

**Stack:** Kotlin Multiplatform + Compose Multiplatform, **Material 3**, Android + iOS (+ Web /
Desktop). Shared code lives under `MobileApp/shared/src/commonMain/kotlin/com/measify/kappmaker/`;
tests under `commonTest`, `jvmTest`, and `androidHostTest`.

**North-star:** correctness *is* conversion. A crash on the paywall, a blank screen on a flaky
network, a use-case that swallows an error, or a red build that blocks the loop destroys trial starts
and word-of-mouth faster than any copy or design flaw ever could. The other playbooks make the app
*want* to convert; this one keeps it from *breaking* on the way there. Every check below ladders up to
"the app does what it claims, on every device, online and off, without losing the user's data."

> **Why apps quietly break.** Rarely a dramatic bug — almost always an unhandled edge: a `Flow` that
> isn't collected lifecycle-aware, a coroutine launched on the wrong dispatcher, an `error` state no
> screen renders, an Android API smuggled into `commonMain`, a snapshot force-recorded to make the
> gate green. Correctness is not heroics; it is **covering the states and respecting structured
> concurrency, consistently.**

---

## 1. Correctness & coroutines

Most "it works on my machine" bugs in this stack are concurrency bugs. Hold the line on structured
concurrency.

- **No `GlobalScope`.** Ever. Work belongs to a scope with a lifecycle — `viewModelScope` in a view
  model, the caller's scope in a use-case. `GlobalScope.launch` leaks and outlives the screen.
- **Dispatchers & main-safety.** UI-thread work stays on the main dispatcher; IO/CPU work moves off
  it with `withContext(Dispatchers.IO)` / `Default`. A suspend function should be **main-safe** —
  callable from the main thread without blocking it. Don't hardcode dispatchers deep in logic; inject
  them (a `DispatcherProvider`) so they're testable and swappable for `StandardTestDispatcher`.
- **Cancellation is cooperative.** Respect it: don't catch `CancellationException` and swallow it
  (re-throw it), check `isActive`/`ensureActive()` in long loops, and use cancellation-aware APIs.
  Suspending calls cancel cleanly; blocking calls (`Thread.sleep`, blocking IO) do not.
- **Exception handling in view models / use-cases.** A failed network/db call must become an `error`
  UI state, not an uncaught throw. Wrap fallible work (try/catch or a `Result`/`runCatching` boundary
  at the use-case layer) and map failures to typed errors — never let a raw exception reach Compose.
- **Flow collection in Compose is lifecycle-aware.** Collect with
  `collectAsStateWithLifecycle()` (not bare `collectAsState()`), so collection pauses when the screen
  is stopped and doesn't burn work in the background. Use `stateIn(scope, WhileSubscribed(5_000), …)`
  for shared upstream flows so they stop when nothing's listening.
- **State holders mutate safely.** A single source of truth (`StateFlow<UiState>` /
  `MutableStateFlow`), updated atomically (`update { }`), never mutating shared mutable state from two
  coroutines without protection.

```kotlin
// A main-safe use-case that maps failure to a typed result, respects cancellation,
// and runs IO off the main thread. Dispatcher injected for testability.
class GetProfileUseCase(
    private val repo: ProfileRepository,
    private val io: CoroutineDispatcher = Dispatchers.IO,
) {
    suspend operator fun invoke(id: String): Result<Profile> = withContext(io) {
        runCatching { repo.profile(id) }
            .onFailure { if (it is CancellationException) throw it } // never swallow cancellation
    }
}
```

---

## 2. State coverage — every screen, every state

A screen is not done when the happy path renders. The #1 correctness gap is a state with no UI: a
blank screen on error, a spinner that never resolves, no offline path.

- **Five states, always:** **loading**, **content**, **empty**, **error**, **offline**. Model them
  explicitly (a sealed `UiState` or fields on a data-class state) so the compiler helps you cover
  them — a `when` over a sealed state forces every branch.
- **No dead blank UI.** Every non-content state renders *something* legible. A `null`/empty list must
  resolve to a designed empty state, never a void.
- **Error recovery exists.** Error and offline states carry a retry affordance that re-runs the
  fetch; a dead-end error with no way forward is a defect.
- **Offline is a first-class state**, not "error". If the app is offline-first, cached content shows;
  if it genuinely needs the network, say so and offer retry.

*Cross-refs:* the **visual** side of these states (skeletons, designed empty/error layouts, no
spinner-on-blank) is **DESIGN_PLAYBOOK §10**; the **wording** of error/empty/loading strings (plain,
specific, no jargon, no em-dashes) is **COPY_PLAYBOOK §4**. This section owns that the state *exists
and is reachable in code*; those own how it looks and reads.

---

## 3. KMP / Compose Multiplatform gotchas

Code in `commonMain` compiles for **every** target. The most common build break is platform-specific
API leaking into shared code.

- **No Android-only (or JVM-only) APIs in `commonMain`.** No `android.*`, `java.io.File`,
  `java.time` (use `kotlinx-datetime`), `java.util.UUID`, `Context`, `Log`, `SharedPreferences`, etc.
  If shared code needs a platform capability, declare an `expect` and provide every `actual`.
- **`expect`/`actual` completeness.** Every `expect` declaration needs an `actual` in **each** target
  source set (`androidMain`, `iosMain`, and any of `jvmMain`/`wasmJsMain`/`desktopMain` the app
  builds). A missing `actual` fails the build for that target — and the auto-gate's `jvmTest` may not
  catch an iOS-only gap, so reason about all targets, not just the JVM.
- **Resources via the multiplatform resource system** (`compose.components.resources`,
  generated `Res.*` / `stringResource`), not Android `R.*` in shared code.
- **Time, locale, formatting, randomness, networking** are platform-sensitive — use multiplatform
  libraries (`kotlinx-datetime`, `kotlinx-coroutines`, Ktor) and inject `Clock`/locale so behavior is
  deterministic and testable, not dependent on the host's timezone or default locale.
- **Threading model differs on iOS.** Don't assume JVM threading guarantees; keep shared logic
  structured-concurrency-clean so it behaves the same on Kotlin/Native.

---

## 4. Data & repository layer

The repository is the boundary between messy IO and clean domain. Bugs here corrupt everything above
them.

- **Single source of truth.** The UI observes one stream (typically DB/cache); network writes *into*
  that source, the UI never reads network and cache in parallel and races them.
- **Offline-first where claimed.** Cached data serves reads; network refreshes the cache. A cache
  miss with no network resolves to a clean empty/offline state, not a crash.
- **Errors are propagated as types, not leaked as exceptions.** The repository catches IO/parse
  failures and returns a typed result or a domain error; raw `IOException`/`SerializationException`
  must never surface in a view model or Compose. The exception boundary lives here and at the
  use-case, per `AiGuidelines/tech/repository.md` / `domain.md`.
- **No blocking IO on the main thread** and no swallowed write failures (a failed save that returns
  "success" is silent data loss).

---

## 5. Edge cases & regression risk

The happy path is the smallest part of the surface. Think adversarially about inputs and lifecycle.

- **Boundary inputs:** null, empty string/list, very large list (does the `LazyColumn` stay smooth?),
  unexpected/malformed server payloads, zero/negative numbers, extreme/long strings that overflow.
- **Lifecycle & process death:** configuration change (rotation), Android process death and restore —
  is essential UI state held in a `ViewModel`/saved state, or lost? A flow restarted on every
  recomposition re-fetches needlessly.
- **Navigation:** back navigation lands somewhere sane; the back stack isn't corrupted; deep links
  resolve and degrade gracefully when their target/argument is missing.
- **Race conditions & double-taps:** a double-tapped button must not fire two purchases / two
  navigations / two network calls — debounce or disable on first tap. Out-of-order async results
  don't clobber newer state (guard with the latest request id, or `flatMapLatest`).
- **Blast radius:** does the change touch shared code (`designsystem/`, a repository, a use-case, a
  common util) used by other screens? Name what else could regress and whether it's covered.

---

## 6. Tests & snapshot hygiene

Tests are the loop's memory. They exist to make a regression *fail the gate*, not to decorate the PR.

- **Test the logic, in the right source set.** Pure/shared logic — use-cases, mappers, view-model
  state transitions, repository behavior with a fake data source — gets a unit test in
  `commonTest`/`jvmTest` (the gate's `:shared:jvmTest` runs these every iteration). Propose concrete
  cases for new branches, especially error/empty/edge paths from §2 and §5.
- **Coroutines test deterministically.** Use `runTest`, a `TestDispatcher`
  (`StandardTestDispatcher`/`UnconfinedTestDispatcher`), and virtual time (`advanceUntilIdle`) — never
  real delays or `Thread.sleep`. Inject the dispatcher (§1) so production code is drivable from tests.
- **UI gets Roborazzi snapshots, recorded deliberately.** A UI change that moves a snapshot requires a
  **deliberate** `:shared:recordRoborazziAndroidHostTest`, after the visual diff is reviewed and the
  change confirmed wanted — noted in `.loop/decisions.md`. **Never auto-record to force the gate
  green**; that is a loop law (SELF_IMPROVE_LOOP "Hard rules"). An unexpected snapshot diff is a real
  regression until proven intentional.
- **No flaky tests.** No reliance on wall-clock, timezone, locale, network, or ordering of a
  `HashMap`/`Set`. A test that passes only sometimes is worse than no test — it erodes trust in the
  gate.

---

## 7. Build & dependency safety

The gate is law (SELF_IMPROVE_LOOP). A change that can't pass the gate can't ship — guard that early.

- **Spotless is non-negotiable.** The change must survive `spotlessApply` + `spotlessCheck`: no
  wildcard imports, no formatting drift, no unused imports. (The orchestrator runs `spotlessApply`,
  but flag obvious violations so they don't surprise the gate.)
- **Compiles on every target.** No API that breaks Android/iOS/wasm/js/desktop (see §3). Remember the
  auto-gate's `jvmTest` won't catch an iOS-only break — reason about the other targets explicitly.
- **No new heavy dependency without a reason.** A new third-party lib is a maintenance, size, and
  multiplatform-support liability; prefer what's already in the catalog. If one's added, it must
  support every target the app builds.
- **No secrets / keys / tokens committed.** API keys, signing material, `.env`-style values, and
  credentials never land in source. Flag any hardcoded secret as a blocker.
- **The no-touch list is off-limits.** Generated build output, CI workflows, signing config, and the
  paths named in `CLAUDE.loop.md` / `.claude/settings.json` are not edited without a human's say-so.

---

## 8. Must-block checklist (these justify a `block` verdict)

A `block` is reserved for "this can break the build or a core flow / lose data". If **any** of these is
true, the verdict is `block` and the finding must name exactly what breaks and how to confirm it:

- [ ] **Build is (or will be) red** — won't compile on a target, `spotlessCheck` fails, or a gate test
      fails (§7).
- [ ] **Crash on a core flow** — launch, onboarding, paywall, purchase/restore, or main screen can
      throw / NPE / ANR for a realistic input (§1, §5).
- [ ] **Data loss** — a write that can silently fail, corrupt the single source of truth, or drop the
      user's state on process death (§4, §5).
- [ ] **Broken offline / dead state** — a reachable state renders nothing, spins forever, or dead-ends
      with no recovery (§2).
- [ ] **Snapshot forced green** — Roborazzi auto-recorded to pass the gate without confirming the
      visual change was intended (§6) — a loop-law violation.
- [ ] **`GlobalScope` / leaked scope / swallowed cancellation** on a path that matters (§1).
- [ ] **Secret committed** or a no-touch path edited without approval (§7).

Anything below this bar is `major`/`minor`/`nit`, not `block`.

---

## 9. Review rubric (the qa-engineer applies this)

For each reviewed change, write findings tagged by severity:

- **blocker** — anything on the must-block checklist (§8): red build, crash on a core flow, data
  loss, broken offline/dead state, forced-green snapshot, leaked scope/swallowed cancellation on a
  real path, committed secret.
- **major** — a real correctness gap that isn't yet a guaranteed break: an uncovered error/empty
  state on a non-core screen, missing test for new logic, wrong dispatcher / non-lifecycle Flow
  collection, exception leaking toward the UI, a race/double-tap risk, blast radius into shared code
  with no coverage.
- **minor** — defensive gap on an unlikely input, a test that could be tighter or more deterministic,
  a slightly suboptimal concurrency choice that isn't a bug.
- **nit** — naming, a redundant `runCatching`, small cleanup.

Tie every finding to a section above (cite it), cite `file:line`, and give a concrete suggested edit —
the dispatcher to inject, the `collectAsStateWithLifecycle` to use, the state branch to add, or the
exact test case to write. A `block` must name what breaks and **how to confirm it** (the failing
command or the input that crashes). Verdict: `ship` / `fix-first` / `block`. Reviews are advisory;
the gate is law — never let a finding here force a box checked on a red build, and never recommend
forcing the gate green.

---

## Sources & credit

Distilled from official guidance — adapt to *this app's* `AiGuidelines/tech/*.md`, don't cargo-cult:
- **Kotlin coroutines** — structured concurrency, dispatchers, cancellation, exception handling —
  [Coroutines guide](https://kotlinlang.org/docs/coroutines-guide.html),
  [Cancellation & exceptions](https://kotlinlang.org/docs/cancellation-and-exceptions.html),
  [Testing coroutines (`kotlinx-coroutines-test`)](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-test/).
- **Compose best practices** — state, lifecycle-aware collection, performance & stability —
  [Compose state & architecture](https://developer.android.com/develop/ui/compose/architecture),
  [`collectAsStateWithLifecycle`](https://developer.android.com/topic/libraries/architecture/compose),
  [Compose performance](https://developer.android.com/develop/ui/compose/performance).
- **Android testing & Roborazzi** — what to test, deterministic tests, screenshot testing —
  [Testing fundamentals](https://developer.android.com/training/testing/fundamentals),
  [Roborazzi](https://github.com/takahirom/roborazzi).
- **Kotlin Multiplatform** — `expect`/`actual`, source sets, multiplatform resources & libraries —
  [KMP docs](https://kotlinlang.org/docs/multiplatform.html),
  [`expect`/`actual`](https://kotlinlang.org/docs/multiplatform-expect-actual.html),
  [`kotlinx-datetime`](https://github.com/Kotlin/kotlinx-datetime).
