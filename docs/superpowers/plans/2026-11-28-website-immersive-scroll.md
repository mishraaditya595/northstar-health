# Website immersive scroll Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Turn every home section below the cinematic intro into a reversible scroll-scrubbed scene over a guarded live WebGL backdrop, with refreshed copy (programs, energy score, trends).

**Architecture:** Pure, unit-tested frame functions map scroll progress (0–1) to scene state; one small engine (`scroll-scenes.mjs`) measures sticky tracks, runs a single rAF loop while a track is visible, and writes CSS custom properties / `data-*` through `setIfChanged`. A separate `backdrop.mjs` draws one low-res fragment-shader canvas whose palette blends by section. Resting CSS is always the finished state; animated rules apply only under `.scenes-ready` inside the no-preference media query.

**Tech Stack:** Astro 7.4.10 static site, vanilla ES modules, WebGL1, `node:test`, Playwright (preinstalled, for manual screenshots only).

**Spec:** `docs/superpowers/specs/2026-11-28-website-immersive-scroll-design.md` (read it first).

All paths below are relative to `apps/website/` unless they start with `docs/`. Run every command from `apps/website/`.

## Global Constraints

- No new dependencies in `package.json`. No smooth-scroll, no scroll interception, no video, no third-party fonts/embeds, no analytics or cookies.
- The cinematic intro (`CinematicIntro.astro`, `home-motion.mjs`, `home-motion.css`) keeps its behaviour; existing tests in `scripts/home-motion.test.mjs` keep passing unchanged.
- Motion gate: reuse `MOTION_QUERY` from `src/scripts/home-motion.mjs` (`'(prefers-reduced-motion: no-preference) and (min-height: 581px)'`). When it does not match, JS is off, or an API is missing, every scene shows its finished state and the backdrop is a static CSS gradient.
- Per-frame writes: only `transform`, `opacity`, SVG `stroke-dashoffset`, and custom properties consumed by those, plus `data-*` attributes that switch between precomputed states. Use `setIfChanged` from `home-motion.mjs`.
- Headings, ledes and text points are always fully readable; only demo panels scrub. Headings reveal word by word **once** on entry, not scrubbed.
- Desktop (≥ 900 px wide) scene track ≈ 220 vh; phones ≈ 150 vh, at most about 1.5 screens of pin per scene. `#details` must still land on the Offline heading.
- Backdrop off when: reduced motion / short viewport (MOTION_QUERY fails), no WebGL or context lost, `navigator.connection?.saveData === true`, `navigator.deviceMemory` defined and `< 4`, or `navigator.hardwareConcurrency` defined and `<= 2`. Undefined values count as not weak. Canvas: DPR capped at 1, backing size ≤ 0.5 × viewport CSS px each axis. Paused when `document.hidden` or when the intro covers the viewport. Lower intensity in light theme.
- Backdrop colours by section: Offline and Training lime/forest (`--lime`/`--performance`, `--hero-from`), Recovery violet (`--sleep`), Privacy teal (`--hero-to`, brightened), finale lime. Read actual token values from `getComputedStyle` at mount so light/dark both work.
- Budget: home page added JS ≤ 12 KB gzipped including shader source (baseline today: 2,864 B gz for the one home script).
- Every demo keeps the text "Illustration · sample values" at ≥ 11 px. Copy only claims: offline logging, backup of finished workouts, plans, exercise library, programs with today's workout on Today, RPE, rest timer, history, weekly volume/time trends, recovery map, Apple Health / Health Connect reads, energy score (computed on the phone, never stored), 7/30-day trends. No watch, no health write-back.
- Legal pages (`privacy`, `terms`, `delete-account`, `support`, `404`) get no backdrop and no new motion.
- Light and dark themes; no horizontal scroll at 320 px; check 390 px and 1440 px.

## Review Focus

1. Anchor jump / reload mid-page (`#details`, `#faq`, restored scroll position): scenes must render the state for the current scroll position immediately on mount, not progress 0. → Task 2 test `mountScenes applies the current progress on first frame`.
2. Reduced motion switched on while scrolling: scenes snap to finished state and the backdrop stops and is replaced by the gradient. → Task 2 and Task 1 tests on `change` listeners.
3. WebGL context lost (common on iOS when backgrounded): no thrown errors, gradient fallback shows. → Task 1 test `mountBackdrop falls back on context loss`.
4. Resize / orientation change (phone ↔ desktop breakpoint at 900 px): track geometry is re-measured; no stale pins. → Task 2 test `re-measures on resize`.
5. Light theme: backdrop and scene colours keep text contrast (no lime glow behind dark-on-light text at full strength). → Task 1 `paletteAt` light-intensity test plus the screenshot check in Task 8.

---

### Task 1: WebGL backdrop

**Files:**
- Create: `src/scripts/backdrop.mjs`, `src/components/Backdrop.astro`, `scripts/backdrop.test.mjs`
- Modify: `src/pages/index.astro` (render `<Backdrop />` right after `<CinematicIntro />`), `src/pages/features.astro` (render `<Backdrop />` at top of content), `src/styles/global.css` (fallback gradient class only)

**Interfaces:**
- Consumes: `MOTION_QUERY` from `src/scripts/home-motion.mjs`.
- Produces:
  - `backdropAllowed(env: { motionOk: boolean, webgl: boolean, saveData?: boolean, deviceMemory?: number, hardwareConcurrency?: number }): boolean`
  - `paletteAt(stops: Array<{ y: number, color: [number,number,number] }>, y: number): [number,number,number]` — stops sorted by `y` (section top in page px); returns the exact colour at or past a stop until the next stop's blend zone (last 30% of the gap before the next stop), smoothstep-blended inside that zone; clamps before first / after last.
  - `renderSize(cssW: number, cssH: number, dpr: number): { w: number, h: number }` — `Math.max(1, Math.round(css * min(dpr,1) * 0.5))` per axis.
  - `mountBackdrop(canvas: HTMLCanvasElement, win: Window): () => void` (returns teardown). Sections opt in with `data-backdrop="lime|violet|teal"`.
  - `Backdrop.astro` renders `<div class="backdrop" aria-hidden="true"><canvas data-backdrop-canvas></canvas></div>`; fixed, full viewport, `z-index:-1`, `pointer-events:none`; the static gradient is the div's own background and the canvas fades in only after the first successful frame (`.is-live`).

- [ ] **Step 1: Write failing tests** in `scripts/backdrop.test.mjs`:
  - `backdropAllowed` true for `{motionOk:true, webgl:true}`; false for each of: `motionOk:false`, `webgl:false`, `saveData:true`, `deviceMemory:2`, `hardwareConcurrency:2`; true for `deviceMemory: undefined, hardwareConcurrency: 8` and for `deviceMemory: 4, hardwareConcurrency: 4`.
  - `paletteAt`: with stops at y 0 (red `[1,0,0]`) and 1000 (blue `[0,0,1]`): `paletteAt(s, 0)` and `paletteAt(s, 600)` deep-equal red; `paletteAt(s, 1000)` and `paletteAt(s, 5000)` equal blue; `paletteAt(s, -50)` equals red; `paletteAt(s, 850)` is strictly between; monotonic in the blue channel over y 700..1000 step 10.
  - `renderSize(1440, 900, 2)` → `{w:720,h:450}`; `renderSize(390, 844, 3)` → `{w:195,h:422}`; `renderSize(0,0,1)` → `{w:1,h:1}`.
  - `mountBackdrop falls back on context loss`: with a fake canvas whose `getContext('webgl')` returns `null`, `mountBackdrop` does not throw and leaves the parent without `.is-live`; with a fake context, dispatching `webglcontextlost` on the canvas removes `.is-live` and stops scheduling frames (count `requestAnimationFrame` calls on a fake `win`).
  - `mountBackdrop stops when reduced motion turns on`: fake `matchMedia` whose `change` listener is fired with `matches:false` → `.is-live` removed, no further rAF.
- [ ] **Step 2:** `npm test` → the new tests FAIL (module not found).
- [ ] **Step 3: Implement `backdrop.mjs`.** WebGL1, one full-screen triangle, one fragment shader: 3–4 octaves of value noise flowing slowly with `u_time`, offset by `u_scroll * 0.0003` and `u_pointer` (fine pointers only, eased), tinted by `u_color` (from `paletteAt` over `[data-backdrop]` section tops, re-measured on resize) and scaled by `u_intensity` (dark 1.0, light 0.45; follow `prefers-color-scheme` changes). Pause on `visibilitychange` hidden and while the `[data-cinematic]` element's bottom is below the viewport bottom (intro still covering). Handle `webglcontextlost` (preventDefault, stop, drop `.is-live`) and `webglcontextrestored` (rebuild). Mount from an inline module `<script>` in `Backdrop.astro` gated by `backdropAllowed`.
- [ ] **Step 4:** `npm test` → all PASS. `npm run build` passes.
- [ ] **Step 5:** Add `data-backdrop` to each home section in `index.astro` (offline/training `lime`, recovery `violet`, privacy `teal`, faq `teal`, cta `lime`) and to the features page main sections (`lime`). Build, open `npm run preview`, confirm the canvas renders below the intro and the gradient shows with reduced motion emulated.
- [ ] **Step 6: Commit** `feat(website): live WebGL backdrop with static fallback`.

### Task 2: Scene engine

**Files:**
- Create: `src/scripts/scroll-scenes.mjs`, `scripts/scroll-scenes.test.mjs`, `src/styles/home-scenes.css`
- Modify: `src/pages/index.astro` (import `home-scenes.css`; mount script)

**Interfaces:**
- Consumes: `setIfChanged`, `MOTION_QUERY` from `home-motion.mjs`.
- Produces:
  - `sceneProgress(top: number, trackHeight: number, viewportHeight: number): number` — `clamp(-top / max(1, trackHeight - viewportHeight), 0, 1)`.
  - `seg(p: number, a: number, b: number): number` — local 0–1 progress of `p` within `[a,b]`, clamped.
  - `mountScenes(doc: Document, win: Window, frames: Record<string, (p: number, ctx: { mobile: boolean }) => SceneState>): () => void` — finds `[data-scene-track="<name>"]`; each has a sticky child `[data-scene-stage]`. `SceneState` is `{ vars?: Record<string, string|number>, attrs?: Record<string, string> }`, applied to the track element (`style.setProperty('--' + k, v)`, `dataset[k] = v`) through `setIfChanged`. Adds `.scenes-ready` to `<html>` only when `MOTION_QUERY` matches and `IntersectionObserver`/`requestAnimationFrame` exist; otherwise does nothing (finished state shows). `ctx.mobile = innerWidth < 900`.
  - CSS: `.scenes-ready [data-scene-track]{height: var(--track, 220vh)}` with `--track:150vh` under 900 px; `[data-scene-stage]{position:sticky; top: <nav-free offset>}` only under `.scenes-ready`. Without `.scenes-ready` tracks are `height:auto` and stages static.

- [ ] **Step 1: Write failing tests** in `scripts/scroll-scenes.test.mjs` (use a minimal fake DOM: objects with `getBoundingClientRect`, `style.setProperty`, `dataset`, `querySelector`; fake `win` with `innerHeight/innerWidth`, `matchMedia`, manual `requestAnimationFrame` queue, `IntersectionObserver` stub that reports all visible):
  - `sceneProgress`: `(100, 2200, 1000)→0`, `(-600, 2200, 1000)→0.5`, `(-1200,2200,1000)→1`, `(-5000,2200,1000)→1`, `(0, 500, 1000)→0` (no NaN when track shorter than viewport).
  - `seg(0.5, 0.4, 0.6)→0.5`, `seg(0.1,0.4,0.6)→0`, `seg(0.9,0.4,0.6)→1`.
  - `mountScenes applies the current progress on first frame`: track rect `top:-600, height:2200`, viewport 1000 → after one rAF tick the frame fn was called with `0.5` and `--x` written.
  - `does nothing without motion`: `matchMedia(...).matches=false` → no `.scenes-ready`, frame fn never called.
  - `snaps to finished state when reduced motion turns on`: fire the media `change` with `matches:false` → `.scenes-ready` removed from `<html>`, inline vars removed from tracks, loop stops.
  - `re-measures on resize`: change `innerWidth` from 1440 to 390, dispatch `resize`, tick → frame fn receives `ctx.mobile === true`.
  - `only loops while a track is visible`: IO reports not intersecting → no rAF scheduled on scroll.
  - CSS check (style of existing CSS tests): in `home-scenes.css`, every `position: sticky` and every `--track` height rule sits inside `@media (prefers-reduced-motion: no-preference)` and under `.scenes-ready`.
- [ ] **Step 2:** `npm test` → new tests FAIL.
- [ ] **Step 3: Implement** `scroll-scenes.mjs` and the base of `home-scenes.css`. Scroll and resize listeners are passive and only schedule a frame; measure rects once per frame.
- [ ] **Step 4:** `npm test` PASS; `npm run build` PASS.
- [ ] **Step 5: Commit** `feat(website): scroll scene engine`.

### Task 3: Offline scene

**Files:**
- Create: `src/scripts/scenes/offline.mjs`, `scripts/scenes.test.mjs` (shared test file for Tasks 3–6)
- Modify: `src/pages/index.astro` (Offline section), `src/styles/home-scenes.css`, `src/styles/home-sections.css` (remove the timed `.is-in` animations for the offline demo only)

**Interfaces:**
- Consumes: `seg` from Task 2.
- Produces: `offlineFrame(p: number): SceneState` with `vars: { bars: 0..4 (signal bars shown), sync: 0..1 }` and `attrs: { saved: '0'|'1'|'2'|'3', online: 'yes'|'no', point: '0'|'1'|'2' }`. Timeline from the spec: 0–0.15 bars 4→0 and `online:'no'` once bars hit 0; 0.15–0.6 saved 0→3 (each set at equal thirds); 0.6–0.72 bars 0→4 and `online:'yes'` after 0.72; 0.72–1 sync 0→1. `point`: 0 while saving, 1 during reconnect/sync, 2 at p ≥ 0.95.

- [ ] **Step 1: Failing tests** (`scripts/scenes.test.mjs`), plus a shared helper `assertSceneContract(frameFn, finished)` used by Tasks 3–6: frame at `p=1` deep-equals `finished`; same output for the same `p` visited ascending and descending over 0..1 step 0.01 (reversible, deterministic); all numeric vars finite and within declared bounds. Offline specifics: `offlineFrame(0)` → `bars:4, saved:'0', online:'yes'`; `offlineFrame(0.15).vars.bars===0` and `online:'no'`; `offlineFrame(0.4).attrs.saved==='2'`; `offlineFrame(0.66).attrs.online==='no'`; `offlineFrame(1)` → `{vars:{bars:4,sync:1},attrs:{saved:'3',online:'yes',point:'2'}}`.
- [ ] **Step 2:** FAIL. **Step 3:** implement; wrap the Offline section in `data-scene-track="offline"`, the demo in `data-scene-stage`; add a 4-bar signal indicator to the demo head; CSS maps `[data-saved]`, `[data-online]`, `--bars`, `--sync` (sync bar uses `transform: scaleX(var(--sync))`), `[data-point]` highlights the matching `.points li` (border colour + opacity 0.55 → 1 on the others, readable at 0.55 is not acceptable: use colour emphasis only, keep text at full opacity). On phones the stage holds heading + demo; points follow after the pin.
- [ ] **Step 4:** `npm test`, `npm run build` PASS. **Step 5: Commit** `feat(website): offline scroll scene`.

### Task 4: Training scene with programs

**Files:**
- Create: `src/scripts/scenes/training.mjs`
- Modify: `index.astro` (Training section), `home-scenes.css`, `home-sections.css` (drop timed tile animations), `scripts/scenes.test.mjs`

**Interfaces:**
- Produces: `trainingFrame(p: number, ctx: { mobile: boolean }): SceneState`.
  - Desktop: `attrs.step: '0'..'4'` (library, programs, log, rest, progress; equal fifths, step 4 at p ≥ 0.8) and per-step local vars `--k` (0–1 within the step); `vars.kg` and `vars.reps` integers counting 65→70 and 8→6 during step 2 (written as text via `attrs`: `attrs.kg`, `attrs.reps`, rendered by CSS `content: attr()` is NOT allowed for main text, so the engine must also support `text?: Record<selector, string>`; add `text` to `SceneState` in Task 2's engine if absent, applied with `setIfChanged` on `textContent`); `vars.ring` 0→1 during step 3 (rest ring from 01:30 to 00:00; `text['.timer-text b']` mm:ss); `vars.bars` 0→1 during step 4.
  - Mobile (`ctx.mobile`): no pin (`--track:auto` for this track via `attrs.mode:'tiles'`); each `.tile` is its own small track `data-scene-track="tile-<n>"` using `tileFrame(p)` → `{vars:{k:p}}`. Engine handles this naturally.
  - Finished state (`p=1` desktop): `step:'4'`, `kg:'70'`, `reps:'6'`, ring 1, bars 1 — and the static (no-JS) markup shows all five items as the existing tile grid plus a new **Programs** tile.
- [ ] **Step 1: Failing tests:** contract helper with the finished state above; `trainingFrame(0.1,{mobile:false}).attrs.step==='0'`; `trainingFrame(0.5,…).attrs.step==='2'` with kg between 65 and 70; at `p=0.7` timer text matches `/^0[01]:\d\d$/`; mobile `trainingFrame(0.5,{mobile:true}).attrs.mode==='tiles'`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. New Programs tile copy (exact): heading `Programs with a plan for today`, body `Follow a multi-week program and today’s workout is waiting on your Today screen. Miss a day and it picks up where you left off.` Demo: a 7-day strip (Mon–Sun), today highlighted, card "Today · Upper body A · 6 exercises". Desktop layout: list of five items on the left (heading + one line each), one large pinned panel on the right that cross-fades between the five demos by `[data-step]`. No-JS/finished: grid of five tiles as today.
- [ ] **Step 4:** tests, build PASS. **Step 5: Commit** `feat(website): training scroll scene with programs`.

> Before writing the Programs copy, confirm in `apps/mobile/lib/features/train/` or `docs/CATALOG.md` that missed days are carried forward; if the app skips them instead, change the second sentence to match the code. Do not guess.

### Task 5: Recovery scene with energy score

**Files:**
- Create: `src/scripts/scenes/recovery.mjs`
- Modify: `index.astro` (Recovery section copy + demo), `home-scenes.css`, `home-sections.css`, `scripts/scenes.test.mjs`

**Interfaces:**
- Produces: `recoveryFrame(p: number): SceneState` → `vars: { wave: 0..1 (0–0.35), energy: 0..1 (0.3–0.65, eased), trend: 0..1 (0.5–0.85) }`, `text: { '[data-energy-value]': integer 0→74, '[data-steps]': '0'→'6,240' (use `countUpText` from `home-reveal.mjs`), '[data-rhr]': 0→58 }` counting during 0.6–1.0; weight stays "No reading" always.
- [ ] **Step 1: Failing tests:** contract with finished `{wave:1, energy:1, trend:1}` and texts `'74'`, `'6,240'`, `'58'`; `recoveryFrame(0)` texts `'0'`; text values never exceed finals.
- [ ] **Step 2:** FAIL. **Step 3:** implement. Copy changes (exact):
  - Lede: `Connect Apple Health or Health Connect and BeyondRep shows your sleep, an energy score and 7 and 30-day trends beside your training. It reads; it never uploads your health data.`
  - Add a point: tag `Energy`, heading `An energy score for right now`, body `Worked out on your phone from your sleep, heart and recent training, so you can decide whether to push or hold back. It is never stored or sent anywhere.`
  - Demo: energy gauge (SVG arc, `stroke-dashoffset` from `--energy`) labelled `Energy · sample`, value 74; 7-day energy trend sparkline (SVG polyline drawn with `--trend`); keep sleep wave, steps, resting HR and the missing weight tile.
  - Before finalising the lede, check `apps/mobile/lib/features/health/` copy for whether "30-day" trends are user-visible; if only 7-day, drop "and 30-day".
- [ ] **Step 4:** tests, build PASS. **Step 5: Commit** `feat(website): recovery scroll scene with energy score`.

### Task 6: Privacy scene

**Files:**
- Create: `src/scripts/scenes/privacy.mjs`
- Modify: `index.astro` (Privacy section), `home-scenes.css`, `scripts/scenes.test.mjs`

**Interfaces:**
- Produces: `privacyFrame(p: number): SceneState` → `vars: { split: 0..1 }` (0.1–0.7, eased) and `attrs: { locked: 'yes'|'no' }` (`'yes'` at p ≥ 0.75).
- [ ] **Step 1: Failing tests:** contract with finished `{vars:{split:1},attrs:{locked:'yes'}}`; `privacyFrame(0).vars.split===0`.
- [ ] **Step 2:** FAIL. **Step 3:** implement. Markup keeps the two existing cards (finished state). Under `.scenes-ready` each list item gets a start offset (custom props `--fx`, `--fy`, computed once at mount from the stage centre by the engine-free helper in this file, `startOffsets(cardRects, centreRect)`) and is placed with `transform: translate(calc(var(--fx) * (1 - var(--split))), calc(var(--fy) * (1 - var(--split))))`; a phone outline in the stage centre fades out as `--split` → 1; lock icon appears on the phone card when `locked`. Unit-test `startOffsets` with plain numbers.
- [ ] **Step 4:** tests, build PASS. **Step 5: Commit** `feat(website): privacy scroll scene`.

### Task 7: Polish — word reveals, magnetic CTAs, page progress, finale

**Files:**
- Modify: `src/scripts/home-reveal.mjs`, `scripts/home-motion.test.mjs` (reveal tests live there today), `index.astro`, `features.astro`, `home-sections.css`, `src/layouts/Base.astro` (progress bar markup only on `cinematic` pages)

**Interfaces:**
- Produces:
  - `splitWords(text: string): string[]` (splits on whitespace, keeps punctuation attached).
  - `magnetOffset(dx: number, dy: number, radius: number, max: number): { x: number, y: number }` — zero outside `radius`, linear falloff to `max` px at centre, direction toward pointer.
  - Heading markup: `.display` headings get `data-words`; at mount (motion on) the script wraps words in `<span class="w" style="--w:i">` with the original text kept in `aria-label` on the heading and `aria-hidden` on the spans; plays once on entry via the existing `is-in` observer.
  - Page progress: a 2 px bar at the top (`transform: scaleX(var(--page))`) driven by the Task 2 engine's scroll handler (`--page` on `<html>`), home only.
  - Finale: make the `.finale` section a short track `data-scene-track="finale"` with `finaleFrame(p)` → `vars.rings` 0..1 (ring scale 0.6→1, rotation) — add `finaleFrame` to `scenes/finale.mjs` with the contract test.
- [ ] **Step 1: Failing tests:** `splitWords('Plan it, lift it, see it add up')` → 8 items with `'it,'` intact; `splitWords('  a  b ')` → `['a','b']`; `magnetOffset(200,0,120,8)` → `{x:0,y:0}`; `magnetOffset(0,0,120,8)` → `{x:0,y:0}`; `magnetOffset(60,0,120,8).x` > 0 and ≤ 8; finale contract with finished `{vars:{rings:1}}`.
- [ ] **Step 2:** FAIL. **Step 3:** implement; magnetic only on `(hover: hover) and (pointer: fine)` and motion on; reset on `pointerleave`.
- [ ] **Step 4:** tests, build PASS. **Step 5: Commit** `feat(website): word reveals, magnetic buttons, page progress and finale`.

### Task 8: Rules, budget and verification

**Files:**
- Modify: `apps/website/AGENTS.md` (motion bullet), `apps/website/README.md` (if it describes motion), `scripts/check-links.mjs` + `scripts/check-links.test.mjs` (JS budget check)

- [ ] **Step 1: Failing test** in `check-links.test.mjs`: `jsBudget(dist, page)` returns the gzipped byte total of the `<script type="module" src>` files referenced by that built page plus inline module scripts; `checkBudget(totalBytes, limit)` returns a problem string when over. Limit for `index.html`: `2864 + 12288` bytes.
- [ ] **Step 2:** FAIL. **Step 3:** implement with `node:zlib` `gzipSync`; wire into the `check-links` main run for `index.html`.
- [ ] **Step 4:** Replace the AGENTS.md motion bullet with: `Motion animates compositor-cheap properties (transform, opacity, SVG strokes and the custom properties feeding them). Home sections may be scroll-linked and reversible; headings and body text stay readable at every scroll position. One WebGL backdrop canvas is allowed on the home and features pages only, guarded as in docs/superpowers/specs/2026-11-28-website-immersive-scroll-design.md. Everything is off with prefers-reduced-motion, short viewports or without JS, and the resting styles show the finished, readable state. Demo panels with sample values say so in text of at least 11 px.`
- [ ] **Step 5: Verify:** `npm test && npm run build && npm run check-links` all pass. Then with `npm run preview` and Playwright (Chromium preinstalled; `require('playwright')`):
  - Screenshots at 1440×900 dark and 390×844 light, scrolled to mid-scene for each scene and to each scene's end; save to `/mnt/project-files/website/immersive/after/` (network mount: trailing slash, write then re-list after ~10 s).
  - Same pages with `reducedMotion: 'reduce'` and with `javaScriptEnabled: false`: every section shows its finished state (assert e.g. offline demo has 3 `Saved on phone` rows visible and `Finished workout backed up` visible).
  - 320×640: `document.documentElement.scrollWidth <= 320`.
  - `#details` navigation: Offline heading top within 0–120 px of the viewport.
  - Chromium trace (`page.tracing` / CDP `Emulation.setCPUThrottlingRate {rate:4}`) while scrolling top→bottom: report the longest task attributable to our scripts; must be < 50 ms.
- [ ] **Step 6: Commit** `chore(website): motion rules, JS budget check`.
