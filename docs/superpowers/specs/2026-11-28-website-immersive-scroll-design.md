# Website: immersive scroll scenes and a live backdrop

**Date:** 2026-11-28 · **Owner:** Adi · **Scope:** `apps/website/` only (home page, plus a light touch on `/features`)

## Intent

Adi wants beyondrep.in to feel immersive and to have a wow factor. The cinematic intro (PR #73, merged and live) is strong, but the home page goes flat right after it: the sections are static cards that fade in once, with small one-shot demos. Adi chose to **polish the whole scroll** rather than add one big moment, and to **relax the site's motion rules** to allow it.

Success: someone who scrolls the home page on a laptop or a phone feels the product working at every section, the page stays fast and readable, and nothing on it claims more than the app does.

## Goals

1. Every home section below the intro becomes a **scroll-scrubbed scene**. The demo panel's state is a pure function of scroll progress (0 to 1): it plays forward when you scroll down, reverses when you scroll up, and never runs on a timer. Headings, ledes and text points are always fully readable at any scroll position; only demo panels scrub. (Builder call, from the builder check.)
2. A **live WebGL backdrop** (one canvas, hand-written shader, no library) sits behind the page below the intro. It is a soft, slowly flowing glow field whose colour blends by section: lime/forest for Offline and Training, violet for Recovery, teal for Privacy, lime again for the finale. It drifts slightly with scroll and, on mouse/trackpad devices, with the pointer.
3. **Shared polish:** section headings reveal word by word, played once when they enter view (not scrubbed, so a heading is never frozen half-shown); a thin page-progress bar; CTA buttons that lean toward the pointer ("magnetic", fine pointers only); the existing card glow stays.
4. **Copy refresh**, limited to what the app already does in the internal TestFlight build and what the site already mentions elsewhere: the Recovery scene shows the **energy score** (sample value, computed on the phone, never stored) and **7/30-day trends**; the Training scene adds **programs** (follow a program; today's workout shows on Today). Adi confirmed on 2026-11-28 that testers' builds have programs.
5. `/features` gets the backdrop and the word-by-word heading reveals only, not scenes.

## Non-goals

- No new runtime dependencies (no GSAP, Lenis, three.js). No smooth-scroll or scroll hijacking: native scrolling only.
- No video, no third-party fonts or embeds, no analytics, no cookies.
- No change to the cinematic intro's behaviour (it keeps its own dark grid and halo; the backdrop starts below it at the seam).
- No motion on the legal pages (`/privacy`, `/terms`, `/delete-account`, `/support`, 404): plain and readable.
- No Apple Watch, Wear OS recording or health write-back claims (the site rules forbid them until released).

## Anti-goals (a failure even if it "works")

- Jank or a hot phone on a mid-range Android; any long task during scroll.
- Text that is hard to read at rest, or a section that is blank/half-drawn when JS is off, reduced motion is on, or the reader jumps straight to an anchor.
- Scroll that feels trapped: pinned sections so long that a phone user has to fling repeatedly to get past one.
- Layout shift, or a worse Largest Contentful Paint than today.
- Any sample number presented as real, or a feature claim the app cannot back up.

## Constraints

- Astro 7 static site, vanilla ES modules, `node:test` unit tests, Cloudflare Pages. CI runs `npm test`, `npm run build`, `npm run check-links`.
- Performance V2 colour tokens, light and dark themes both. Check 320 px, 390 px and desktop widths.
- `prefers-reduced-motion: reduce`, no JS, or a short viewport (under 581 px tall, matching the intro's rule): every scene shows its **finished state** as plain, static HTML/CSS, and the backdrop is replaced by a static CSS gradient.
- Backdrop also off (static gradient) when: WebGL is unavailable or the context is lost, `navigator.connection.saveData` is true, or the device looks weak: `navigator.deviceMemory` is exposed and below 4, or `navigator.hardwareConcurrency` is 2 or less. Missing values count as "not weak", so iPhones (which expose no `deviceMemory`) get the backdrop. (Builder call.) Rendered at reduced resolution (device pixel ratio capped at 1, canvas at most 0.5 of the viewport's CSS pixels, scaled up with CSS), and paused when the tab is hidden or the canvas is fully covered by the intro.
- Budget: the home page's added JS, shader source included, at most 12 KB gzipped (builder call); the existing one-shot `data-reveal` fades stay for the FAQ, `/features` and the section heads, and the timed count-ups inside demos become scroll-driven; the shader compiles once; one `requestAnimationFrame` loop that only runs while a scene or the backdrop is on screen.
- Scene motion animates transform, opacity, SVG stroke offset and CSS custom properties read by those; no layout-affecting properties per frame. Writes go through the existing `setIfChanged` helper.

## Approaches considered

1. **Native scroll scenes, no library** (chosen). Scroll progress per scene computed in a small script (the same pattern as `home-motion.mjs`), pure frame functions unit-tested in Node, CSS reads custom properties. Smallest and fastest, consistent with the existing tested code; each scene is hand work.
2. **GSAP + smooth scroll.** Easiest choreography, but about 60 KB added and smooth scroll feels floaty on phones. Rejected for weight and feel.
3. **Either plus a WebGL backdrop.** Most ambient wow, costs battery on weak phones. **Adopted together with 1**, with the guards above.

Adi picked **"Native scenes + WebGL backdrop"** on 2026-11-28.

## The scenes

Each scene is a tall track with a sticky stage inside it. Desktop (≥ 900 px wide): track about 220 vh, stage pinned for the middle. Phones: track about 150 vh, with the demo pinned under the heading and the text points following after the pin ends, so a phone user scrolls through at most ~1.5 screens of pin per scene. Progress 0 is when the stage pins, 1 when it releases.

1. **Offline: "Built for the gym, not for signal bars."** The existing Bench press panel becomes the stage.
   - 0–0.15: signal indicator drops bar by bar to "No signal" (caution colour).
   - 0.15–0.6: sets 1, 2, 3 tick in one at a time, each "Saved on phone ✓".
   - 0.6–0.72: signal bars return.
   - 0.72–1: backup bar fills, label flips to "Finished workout backed up".
   - The three points on the left light up in step (saved locally → backs up later → multi-device).
2. **Training: "Plan it, lift it, see it add up."** Desktop: one large demo panel pinned on the right that morphs through five states while the list on the left highlights the matching item: library search filters (results appear), programs (a week strip with today's workout highlighted), set logging (weight and reps count up from last time), rest timer (ring winds down 01:30 → 00:00), progress (weekly bars grow, muscle chips light). Phones: no single pinned panel; the existing tiles stack and each tile's mini demo scrubs as it crosses the middle of the screen.
3. **Recovery: "Your recovery, next to your training."** Sleep wave draws left to right; the energy score gauge sweeps to a sample value with a "Sample" label; a 7-day energy trend line draws (settled sample score, not the "still learning" state; builder call); steps and resting heart rate count up; weight stays "No reading", explicitly showing missing as missing. Text says energy is worked out on the phone and never stored.
4. **Privacy: "Your data stays yours."** Data chips start together inside a phone outline. As you scroll, "Email address" and "Finished workouts" lift up into the cloud card; "Apple Health / Health Connect data", "Unfinished workouts" and "Plans and templates" settle into the phone card with a lock. The resting state is today's two cards.
5. **FAQ:** unchanged content; headings reveal; no pin.
6. **Finale:** CTA rings scale out and the headline's words assemble as it scrolls in; buttons are magnetic on fine pointers.

Every demo keeps an "Illustration · sample values" note in text of at least 11 px.

## Code shape (builder may refine)

- `src/scripts/scroll-scenes.mjs`: pure `sceneProgress(top, trackHeight, viewportHeight)` and one frame function per scene, e.g. `offlineFrame(p)` returning `{ bars, setsSaved, syncFill, online, activePoint }`; `mountScenes(doc, win)` observes tracks with `IntersectionObserver`, runs one rAF loop while any is visible, writes custom properties and `data-*` state with `setIfChanged`. No-op under reduced motion, short viewports, or missing APIs; listens for reduced-motion changes and snaps to the finished state.
- `src/scripts/backdrop.mjs`: pure `paletteAt(sectionStops, scrollY)` (blend between section colours), `backdropAllowed(env)` (the guard list above), `renderScale(dpr, width)`; `mountBackdrop(canvas, win)` handles WebGL1 setup, one fragment shader (a few octaves of value noise, not raymarching), context loss, visibility pause and theme (lower intensity in light mode).
- `src/styles/home-scenes.css`: resting styles are the finished state; animated styles apply only under `.scenes-ready` inside `@media (prefers-reduced-motion: no-preference)`.
- Word-reveal and magnetic buttons can live in `home-reveal.mjs`, extending what is there.
- Update `apps/website/AGENTS.md` motion rule to the relaxed version: scroll-linked, reversible scenes and one guarded WebGL canvas are allowed; the cheap-properties, finished-at-rest, reduced-motion and no-JS rules stay.

## Testing

- Unit (TDD, `node:test`): `sceneProgress` clamping; each frame function is deterministic, reversible (same output scrolling down or up), bounded, starts at the "before" state at 0 and equals the resting/finished state at 1; `paletteAt` returns the exact section colour inside a section and blends only between neighbours; `backdropAllowed` covers each guard; CSS checks in the existing style (animated rules only inside the no-preference media query and `.scenes-ready`).
- Build and `check-links` pass.
- Manual/Playwright: screenshots at 1440 × 900 dark and 390 × 844 light, before and after, including mid-scene frames; reduced-motion run shows every section finished; JS-disabled run shows every section finished; no horizontal scroll at 320 px.
- Performance check: Chrome trace with 4× CPU throttling while scrolling the full page shows no long tasks over 50 ms from our code.

## Left to the builder

Exact easing curves, colour stops within the token palette, shader details, per-scene track lengths within the bounds above, and how the Training desktop panel is marked up, as long as the finished state is readable without JS.

## Open risks

- Safari: sticky + transformed children and WebGL context limits need a real-device check (no Mac here). Called out in the PR as not run.
- Long pinned tracks change page length; anchor links (`#details`) must still land on the section heading.
