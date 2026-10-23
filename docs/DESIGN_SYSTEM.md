# Northstar Performance V2 — design system

**Source of truth:** `prototypes/performance-v2/`. The browser loads `styles.css`, then `performance-v2.css`, then `performance-v2-theme.css`; later overrides win. The older green-and-serif look is *not* the current reference.

## Character
A bold athletic performance instrument panel, not a bland clinical dashboard. Strong compact headlines, opaque graphite surfaces, small but legible signal panels, an expressive deep-green workout hero, lime actions, and purposeful purple sleep signals. Avoid generic outlined Material defaults, universal glass blur, decorative gradients on every card, or invented readiness scores.

| Semantic token | Dark | Light |
| --- | --- | --- |
| Canvas | `#0B0F13` | `#F2F5F1` |
| Surface | `#171E24` | `#FFFFFF` |
| Surface soft | `#202932` | `#EAF0EA` |
| Ink | `#F5F7F6` | `#172B22` |
| Secondary ink | `#A5B0B8` | `#586E62` |
| Border | `#34404A` | `#D7E2D8` |
| Performance | `#D6FF60` | `#316946` |
| Sleep | `#C1A9FF` | `#6650AB` |
| Caution | `#FFD18B` | `#896123` |
| Destructive | `#FF8587` | `#9F3041` |

Keep lime (`#D6FF60`) as the CTA inside **dark hero** in both modes; ordinary small text on light surfaces uses forest green. Hero background is a dark green-to-teal gradient (`#253D2E` to `#0D2225`) with understated concentric accents. Large headlines such as **SHOW UP. GET STRONG.** use system sans bold 850–950, tight tracking, uppercase; page headings 30–38sp, body 14–16sp, supporting labels 11–13sp with accessibility scaling. Do not copy the HTML's unreadable 9px UI labels.

Spacing uses 4px rhythm (8, 12, 16, 20, 24, 32), page gutters 16–24, cards 20–24 radius, heroes 28, controls 12–16. Numeric data is tabular, with visible units/source/date. Practical tap sizes >=48dp; honor dynamic text, focus, voice assist and reduced motion.

## Components to translate
- `.v2-hero`: workout call to action, deep-green accent, distinct hierarchy
- `.v2-stat`, `.v2-snapshot`: quantified daily metrics
- `.v2-week`: week session adherence
- `.v2-health-feature`: category-specific sleep block, no clinical inference
- `.v2-set`: set logger with explicit completed state
- `.bottom-nav`: Today / Train / Progress / Health on compact; rail on tablets
- `.theme-switch`: accessible appearance choice in both modes

## Layout and acceptance
320–599: single-column, nav bottom, 2-column metric cards only if text fits. 600–839: side rail and constrained content. 840+: side rail, up to ~1120dp dashboard and optional secondary panel. Don't stretch content just because tablet width is available. Test 320, 390, 700, 1024, 1366 logical widths in light/dark, landscape, split screen and 200% text scale.

The HTML is a simulated **393×852 phone**, not a reference for tablet composition. Flutter must **adapt** the aesthetic, not copy absolute CSS positioning or unsupported tiny controls.
