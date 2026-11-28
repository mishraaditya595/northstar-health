# Website agent instructions

Inherited rules: ../../AGENTS.md. This folder is the static marketing and legal site for https://beyondrep.in (Astro, deployed by Cloudflare Pages). It shares no code with the apps.

- Run from here: `npm ci`, `npm test`, `npm run build`, `npm run check-links`. Node 22.23.4 or newer.
- **Describe only what the shipped app does.** Never claim ratings, user counts, awards, medical benefits, watch recording or health write-back until they are real. "Coming later" lists are fine.
- **Legal pages must match the code and `docs/PRIVACY_POLICY_INPUTS.md`.** Any change to what the app collects, syncs or shares (see its section 11) needs the privacy page, delete-account page and store forms updated in the same release. Keep `SITE.legalDraft` true until the open questions there are answered.
- **No tracking.** No analytics, tag managers, cookies, third-party fonts or embeds. Cloudflare Web Analytics (cookie-free) may be enabled from the Cloudflare dashboard only.
- No secrets or hosted identifiers in this folder. Contact addresses are role addresses on the project domain, never a personal email. Owner-approved exception (2026-11-26): `privacyEmail` in `src/site.ts` is the owner's mailbox until privacy@ routing exists.
- Every page uses `layouts/Base.astro` (or `Legal.astro`) so it gets a title, description, canonical URL, share image and JSON-LD. `npm run check-links` fails the build otherwise.
- Colours come from the Performance V2 tokens in `docs/DESIGN_SYSTEM.md`; light and dark both supported. Check 320 px, 390 px and desktop widths.
- The home page intro (`CinematicIntro.astro`) is always dark, using the dark token values pinned in `home-motion.css`; the rest of every page follows the reader's theme.
- Motion animates compositor-cheap properties (transform, opacity, SVG strokes and the custom properties feeding them). Home sections may be scroll-linked and reversible; headings and body text stay readable at every scroll position. One WebGL backdrop canvas is allowed on the home and features pages only, guarded as in docs/superpowers/specs/2026-11-28-website-immersive-scroll-design.md. Everything is off with prefers-reduced-motion, short viewports or without JS, and the resting styles show the finished, readable state. Demo panels with sample values say so in text of at least 11 px.
- Pin exact dependency versions and commit `package-lock.json`.
