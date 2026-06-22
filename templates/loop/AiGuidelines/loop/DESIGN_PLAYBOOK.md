# Design playbook — premium mobile visual craft

The shared reference for the self-improve loop's visual-craft agents (`ui-ux-reviewer`,
`delight-specialist`) and the `orchestrator` — used at **build time and review time**. It is the
**visual-craft lens**: what "premium" looks like on mobile, which levers separate a polished app from
generic "AI slop", and how to judge a change. The app's own `AiGuidelines/project/ui_ux.md` holds
*this app's* specific visual language (brand colors, font choices, mood) — read that for the product
decisions; read this for the principles, the ready-to-use Compose tokens, and the review rubric.

**Stack:** Kotlin Multiplatform + Compose Multiplatform, **Material 3** (`androidx.compose.material3`),
Android + iOS. Tokens live in the `designsystem/` module; screens consume them, never raw values.

**North-star:** premium feel is not decoration — it is conversion and retention. A screen that looks
trustworthy and considered converts trials and earns the word-of-mouth that `GROWTH_PLAYBOOK.md` §6
depends on. Every lever below ladders up to "the user believes this app is worth paying for."

> **Why apps end up looking like slop.** Almost always the same root cause: **magic numbers instead
> of a system.** Random paddings, three competing accent colors, every text the same weight, default
> M3 purple, pure-black dark mode, drop-shadow on everything. Premium UI is not talent or creativity
> — it is **constrained scales applied consistently** (Refactoring UI's central thesis). Fix the
> system and the slop disappears.

---

## 1. Design tokens, not magic numbers (the #1 lever)

Everything visual routes through the `designsystem/` module. A hardcoded `16.dp`, `Color(0xFF6750A4)`,
or `fontSize = 18.sp` inside a `*Screen*.kt` is the single most common slop tell and the first thing
to flag.

- All spacing comes from a `Spacing` scale; all type from `MaterialTheme.typography`; all color from
  `MaterialTheme.colorScheme` (or a semantic extension); all radii from `MaterialTheme.shapes`.
- Adding a one-off value is allowed **only** by adding it to the scale, never inline. If a screen
  needs a value the scale doesn't have, the scale is wrong — fix the scale.
- This is what makes spacing rhythm, color harmony, and dark mode "just work" everywhere at once.

---

## 2. Spacing & layout rhythm

A consistent spacing scale on an **8pt grid** (with 4pt half-steps) is what makes a layout feel
intentional instead of arbitrary.

- **Scale:** `4, 8, 12, 16, 24, 32, 48, 64` (dp). Don't invent `13.dp` or `21.dp`.
- **Grouping by space:** related elements sit closer; unrelated groups sit farther apart. Section
  gaps **must** be visibly larger than element gaps — this is how the eye parses structure without
  borders. Equal spacing everywhere reads as flat and cheap.
- **Generous by default:** start with more whitespace than feels necessary, then tighten. Cramped
  UIs read as low-quality; let hero content breathe.
- **Consistent screen gutter:** one horizontal inset for the whole app (typically `16.dp` phones,
  `24.dp` larger), applied uniformly — not a different margin per screen.
- **Safe areas:** respect status bar, notch/Dynamic Island, and the home indicator
  (`WindowInsets`/`safeDrawing`); never let content or a bottom CTA collide with system UI.
- **Alignment & optical alignment:** establish a left edge and keep to it; center only deliberately.
  Optically center glyphs that aren't mathematically centered (play triangles, icons with built-in
  padding).

```kotlin
// designsystem/Spacing.kt
import androidx.compose.ui.unit.dp
object Spacing {
    val xxs = 4.dp; val xs = 8.dp; val sm = 12.dp; val md = 16.dp
    val lg = 24.dp; val xl = 32.dp; val xxl = 48.dp; val xxxl = 64.dp
}
val screenGutter = Spacing.md   // one app-wide horizontal inset
```

---

## 3. Typography

Type carries hierarchy. Most slop has correct text and no hierarchy — everything the same size and
weight. Map to **Material 3 type roles** (Display / Headline / Title / Body / Label, each L/M/S) and
use them by role, not ad hoc.

- **Hierarchy via three levers — size, weight, AND color** — not size alone. A muted-color, regular
  16sp caption beside a bold high-contrast 16sp label reads as clearly secondary without changing
  size. Use a tonal step (`onSurfaceVariant`) for secondary text.
- **Coherent scale:** distinct, non-adjacent steps. Body 16sp minimum for reading; don't ship 13sp
  body. Avoid two sizes one point apart — they look like a mistake, not a hierarchy.
- **Line height & measure:** ~1.4–1.5× for body; tight leading for large display. Keep long-form
  measure readable on tablets (don't run paragraphs edge-to-edge).
- **Weight & tracking:** large display can take slightly negative tracking; small caps/labels take
  positive tracking. Two families max (often one family + weights). Don't mix three typefaces.
- **Dynamic type:** size in `sp`, respect the OS text-size setting, verify layouts don't break at
  large sizes. Never disable scaling.

```kotlin
// designsystem/Type.kt — a coherent M3 type scale (weights/tracking tuned for hierarchy)
import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
val AppTypography = Typography(
    displaySmall  = TextStyle(fontSize = 36.sp, lineHeight = 44.sp, fontWeight = FontWeight.Bold,     letterSpacing = (-0.5).sp),
    headlineSmall = TextStyle(fontSize = 24.sp, lineHeight = 32.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    titleMedium   = TextStyle(fontSize = 18.sp, lineHeight = 24.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 0.sp),
    bodyLarge     = TextStyle(fontSize = 16.sp, lineHeight = 24.sp, fontWeight = FontWeight.Normal,   letterSpacing = 0.15.sp),
    bodyMedium    = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Normal,   letterSpacing = 0.15.sp),
    labelLarge    = TextStyle(fontSize = 14.sp, lineHeight = 20.sp, fontWeight = FontWeight.Medium,   letterSpacing = 0.1.sp),
)
```

---

## 4. Color system

Color is where slop is loudest: the default M3 purple shipped untouched, or three saturated accents
fighting each other. A premium palette is **mostly neutral with one disciplined accent.**

- **60-30-10:** ~60% neutral surface/background, ~30% secondary surfaces/containers, ~10% accent for
  the primary action and key highlights. The accent should be rare enough that it always means
  "act here". **One** brand accent — a second "accent" is almost always a mistake.
- **Design the neutral ramp:** a true app needs a designed grey/neutral scale (surface, surface
  variant, outline, on-surface, on-surface-variant), not pure `#FFFFFF`/`#000000` slammed together.
  Hierarchy should survive in **grayscale first** — add color last (Refactoring UI). If it only works
  because of color, the structure is weak.
- **Semantic tokens, not raw hex:** screens reference `MaterialTheme.colorScheme.primary` /
  `surface` / `error`, never `Color(0xFF…)`. Replace the default `colorScheme` seed/values in
  `Color.kt`+`Theme.kt` — shipping stock M3 purple is the most recognizable AI-default tell.
- **Contrast (WCAG):** body text ≥ 4.5:1, large text/UI ≥ 3:1, in **both** themes. Never encode
  meaning by color alone (pair with icon/label/shape).
- **Dark mode is not "invert":** use Material 3 **surface tonal elevation** — higher surfaces are
  slightly lighter, not floating on shadows. **Never pure black** (`#000000`) for large surfaces — it
  smears on OLED and looks harsh; use a near-black like `#0F1115`. Re-check every accent for contrast
  on dark. Avoid muddy/clashing gradients; a subtle one-hue gradient beats a rainbow.

```kotlin
// designsystem/Color.kt — replace the default seed; define BOTH schemes explicitly
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.ui.graphics.Color
val LightColors = lightColorScheme(
    primary = Color(0xFF2563EB), onPrimary = Color(0xFFFFFFFF),       // one disciplined accent
    surface = Color(0xFFFFFFFF), onSurface = Color(0xFF111418),
    surfaceVariant = Color(0xFFF1F4F9), onSurfaceVariant = Color(0xFF5A6472),
    outline = Color(0xFFD3D9E2), error = Color(0xFFDC2626),
)
val DarkColors = darkColorScheme(
    primary = Color(0xFF6B9CFF), onPrimary = Color(0xFF06122B),
    surface = Color(0xFF0F1115), onSurface = Color(0xFFE7EAF0),        // near-black, not #000000
    surfaceVariant = Color(0xFF1A1E26), onSurfaceVariant = Color(0xFF9AA4B2),
    outline = Color(0xFF2A2F3A), error = Color(0xFFFF6B6B),
)
```

---

## 5. Elevation & depth

Depth should be quiet and consistent. "A drop shadow on every card" is slop.

- **One elevation scale**, used by role: most surfaces are flat (level 0–1); reserve real elevation
  for things that genuinely float (FAB, bottom sheet, menu, dialog).
- **Prefer M3 tonal elevation** (surface tint) over heavy shadows, especially in dark mode where
  shadows are nearly invisible — separate surfaces by tone instead.
- **Hairline borders** (`outline`, ~1.dp) are often a cleaner separator than a shadow for cards and
  list rows. Pick borders **or** shadows for a given component family — not both, not randomly mixed.
- Shadows, when used, are soft and low-spread — never a hard dark halo.

---

## 6. Shape & radius

- **One radius scale** (e.g. `4, 8, 12, 16, full`) in `MaterialTheme.shapes`; apply by component size
  (chips/small `8`, cards `12–16`, sheets/dialogs `16–28`, pills `full`). Mismatched radii across
  cards/buttons on the same screen is an instant tell.
- Keep radius proportional to component size; a tiny 6dp control with a 24dp radius looks wrong.
- Be consistent app-wide: don't mix sharp rectangles and heavily-rounded cards without intent.

---

## 7. Components — no stock-default look at hero moments

Default M3 components are a fine baseline for utility screens, but onboarding finale, paywall, and
success states must look authored, not scaffolded.

- **Buttons:** clear primary/secondary/tertiary hierarchy (filled → tonal → text). **One** primary
  action per screen. Full-width primary CTA at the bottom is the mobile default; honest,
  benefit-oriented labels (not bare "Submit"). Visible pressed/disabled/loading states.
- **Cards:** consistent internal padding (`Spacing.md`), one radius, one separator strategy (§5);
  don't nest cards in cards.
- **Text fields:** labeled, with real focus, error, and helper-text states; correct keyboard type
  and `imeAction`; never a bare underline with no label.
- **Lists:** consistent row height and inset, aligned leading icons/avatars, clear dividers or
  spacing (not both); `LazyColumn` with stable keys.
- **App bar / bottom nav / sheets:** consistent height, icon size, and active/inactive treatment;
  use `gorhom`-style modal bottom sheets for choices rather than stock OS dialogs at hero moments.

---

## 8. Iconography

- **One icon family**, one style (outline *or* filled — pick per role, not per whim). Don't mix
  Material Symbols with a second set.
- Consistent optical sizes (e.g. `20`/`24`) and stroke weight; align icons to text baselines and
  keep a consistent icon↔label gap.
- **Never emoji as UI icons.** Emoji render differently per platform and read as a prototype.

---

## 9. Motion tokens (shared scale; expression belongs to delight)

This section defines the **shared duration/easing tokens** so motion is consistent; the
`delight-specialist` owns *where* and *how expressively* to animate (hero moments, haptics,
spring physics, personality). Keep tokens here; keep choreography there.

- **Durations:** micro-feedback `100–150ms`, standard transitions `200–300ms`, large/screen
  `300–400ms`. Faster than it feels you need; sluggish UI reads as cheap.
- **Easing:** a standard emphasized easing for most moves (M3 `Easing.bezier(0.2, 0, 0, 1)`-style);
  springs for interactive/gesture-driven motion. Don't scatter ad-hoc cubic-beziers per screen.
- **Purposeful only:** motion clarifies state change or relationship; gratuitous animation is slop.
  Always respect reduce-motion.

```kotlin
// designsystem/Motion.kt
object Motion {
    const val durFast = 120; const val durStandard = 250; const val durLarge = 350  // ms
    // easing/spring specs defined alongside, consumed via animationSpec = ...
}
```

---

## 10. Empty, loading & error states

These are part of the visual system, not afterthoughts (personality/craft is the delight lane; the
*structure* is yours).

- **Loading:** skeletons that match final layout over spinner-on-blank; reserve space to avoid
  layout shift.
- **Empty:** a designed state with a clear next action — never a blank screen or a bare "No data".
- **Error/offline:** legible, on-brand, with a retry affordance; never a raw stack trace or a
  dead-end.

---

## 11. Anti-slop checklist (run this every UI review)

Flag any that are true — each is a recognizable "AI-generated UI" tell:

- [ ] Hardcoded `dp`/`sp`/`Color(0x…)` in a `*Screen*.kt` instead of design-system tokens (§1).
- [ ] Spacing off the 8pt grid, or equal spacing with no grouping hierarchy (§2).
- [ ] Flat type hierarchy — everything similar size/weight; secondary text not tonally muted (§3).
- [ ] Default Material 3 **purple** seed shipped untouched (§4).
- [ ] More than one accent color competing for attention (§4).
- [ ] Pure black `#000000` large surfaces in dark mode, or dark mode that's a naive invert (§4).
- [ ] Contrast below WCAG in either theme; meaning carried by color alone (§4).
- [ ] Drop shadow on every surface, or shadows + borders mixed at random (§5).
- [ ] Inconsistent corner radii across cards/buttons on one screen (§6).
- [ ] Stock-default components at a hero moment (paywall/onboarding finale/success) (§7).
- [ ] Two icon families, mismatched icon sizes, or emoji used as icons (§8).
- [ ] Everything centered / no consistent left edge / no clear primary CTA (§2, §7).
- [ ] Spinner-on-blank loading, blank empty states, raw error text (§10).

---

## 12. Review rubric (the visual-craft reviewer applies this)

For each reviewed change, write findings tagged by severity:

- **blocker** — fails accessibility (contrast/labels/dynamic-type breakage), or ships a state that's
  broken/unreadable (clipped layout, content under system UI, illegible dark mode).
- **major** — a systemic slop tell: hardcoded values instead of tokens, default purple, no type
  hierarchy, competing accents, inconsistent radii, stock components at a hero moment.
- **minor** — spacing rhythm off, weak grouping, suboptimal elevation/shape choice, icon
  inconsistency.
- **nit** — small optical/alignment polish.

Tie every finding to a lever above (cite the section), cite `file:line`, and give a concrete
suggested edit — ideally the token or `colorScheme`/`typography` reference to use instead of the
hardcoded value. Verdict: `ship` / `fix-first` / `block`. Static visual quality is this lane's job;
motion/haptics/personality belong to `delight-specialist` (note those under Out of scope).

---

## Sources & credit

Distilled from design authority — adapt to *this app's* `ui_ux.md`, don't cargo-cult:
- **Refactoring UI** (Wathan & Schoger) — hierarchy via size/weight/color, constrained spacing &
  shadow scales, grayscale-first color, systematic palettes — [refactoringui.com](https://refactoringui.com/).
- **Material 3** — type roles & scale, color roles, tonal elevation, shape & motion tokens —
  [Typography](https://m3.material.io/styles/typography/applying-type),
  [Color system](https://m3.material.io/styles/color/system/overview),
  [Elevation](https://m3.material.io/styles/elevation/overview). M3 **Expressive** (Google I/O 2025):
  emphasized type, physics-based motion, shape morphing.
- **Apple Human Interface Guidelines** — iOS conventions, safe areas, legibility, Dynamic Type —
  [developer.apple.com/design/human-interface-guidelines](https://developer.apple.com/design/human-interface-guidelines).
- **Compose Material 3** theming (`Color.kt` / `Type.kt` / `Theme.kt` / `Shape.kt`) —
  [developer.android.com/develop/ui/compose/designsystems/material3](https://developer.android.com/develop/ui/compose/designsystems/material3).
