# Replicating a design the owner gave you

When the owner hands over a design — a screenshot, an exported mockup, an HTML page, a zip of
screens — the target stops being "make it look good" and becomes "make it look like **this**".
Those are different jobs and they pull in opposite directions, so this brief takes priority over
taste for every screen that has a reference.

**The reference wins every aesthetic argument.** Not your judgement, not the design system's
defaults, not what would convert better. If you think the reference is wrong, build it as given and
say so in a message — the owner decides.

## 1. Take the reference in

Everything lands in `AiGuidelines/design/reference/`, one file per screen where possible, named for
the screen: `home.png`, `paywall.png`, `onboarding-1.png`.

| What they send | What to do |
|---|---|
| Screenshot / photo over Telegram | The message carries an `image_path` — copy that file into the folder under a screen name. Do it immediately; the temp file will not survive. |
| Zip / folder of screens | Unpack into the folder, then rename to screen names. Delete anything that is not a design. |
| HTML/CSS page | Keep the **source**, not just a render. It has exact hex values, pixel spacing, radii and font names — worth more than any screenshot. |
| Figma **link** | You cannot open it; it needs their login. Ask for PNG or SVG exports of each frame, or a copied CSS block per element. Say this plainly instead of guessing at the design. |
| `.fig` file | Same — it is a binary Figma needs to open. Ask for exports. |
| A written description only | That is not a reference. Build it, then use the normal UI/UX milestone instead of this one. |

Write `AiGuidelines/design/reference/README.md` listing each file and which screen it maps to. Note
anything the owner said out loud about it ("ignore the header, I only want the cards"), because that
context is invisible in a PNG and you will lose it by morning.

## 2. Build the screen, then look at it

Never judge a screen from its Kotlin source. Source shows intent; the render shows truth.

```bash
cd MobileApp && ./gradlew :shared:recordRoborazziAndroidHostTest
```

Every `@Preview` becomes a PNG in `shared/src/androidHostTest/snapshots/<Class>_<method>.png`. If the
screen has no `@Preview`, add one (pure overload + `AppTheme`) — no emulator, no device, ~25s.

## 3. Compare, fix, compare again

Per screen, one item in `PLAN.md`. Each pass:

1. Render the screen to a PNG.
2. Hand **both images** to `design-fidelity-reviewer` — the reference and the render.
3. It returns a score out of 100, per-dimension marks, and ranked findings.
4. Fix the findings, biggest first. Structure and colour before radii and shadows: a 2dp icon
   offset is invisible next to a wrong background.
5. Re-render, re-compare. Log each pass's score in `.loop/decisions.md`.

**Done when the reviewer says MATCH** (score ≥ 90, nothing above a minor finding).

## 4. Stop before it becomes a treadmill

"Until it is identical" has no natural end, and an unbounded pixel chase will eat a whole night on
one screen. Three brakes, and any one of them ends the screen:

- **MATCH** — the reviewer is satisfied. Tick it and move on.
- **Six passes on one screen.** Stop, record the best score reached and what is still off.
- **Diminishing returns** — two passes in a row that gain fewer than 3 points. You are polishing
  something that is not the real problem. Stop.

When you stop short of MATCH, write the residual gap into
`AiGuidelines/design/reference/README.md` as a known deviation, with the reason. Then say it in the
milestone message. An honest "the reference uses a font we do not have a licence for, so headings
are Inter instead of Söhne" is worth far more than silently shipping something that looks 80% right
and never mentioning why.

Deviations that are *impossible*, not merely unfinished — a licensed font, a CSS-only effect, a
native control that looks different by design — are not failures. Name them once and stop retrying
them; a loop that keeps attacking an impossible gap is exactly the stall the guard will kill.

## 5. The conflict with the UI/UX milestone

`ui-ux-reviewer` is paid to have opinions about how a screen should look. On a screen with a
reference, those opinions are out of scope and will quietly drag the build away from what the owner
asked for.

So, for referenced screens:

- **Design replication runs first**, before the UI/UX milestone.
- In the UI/UX milestone, `ui-ux-reviewer` may only raise things that are **not** matters of taste:
  contrast that fails accessibility, tap targets too small to hit, text that truncates on a small
  screen, a missing loading/empty/error state.
- Even then it does **not** silently change the look. It reports the conflict, the owner is told at
  the milestone boundary, and they choose. "Your design's button text is 11pt on a light grey — it
  is hard to read and fails contrast. Keep it as designed, or bump it?"
- Screens with **no** reference get the normal, full UI/UX treatment.

## 6. What the owner hears

They gave you a design; they want to know it landed. At the milestone boundary send **one** message:
which screens now match, their scores, which fell short and why, and any deviation they need to
decide on. Attach a render or two — they asked for a look, so show them one.

Not per screen. Not per pass. One message at the end of the milestone.
