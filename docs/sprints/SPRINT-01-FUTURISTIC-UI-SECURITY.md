# Sprint 1 — Futuristic UI Foundation + Frontend Security Hardening

- **Repository**: `residence-proprietaires`
- **Branch**: `feat/sprint-ui-security`
- **Baseline**: `9718d9f` (`app-v2-rc1-20260820`) — untouched throughout, confirmed ancestor of every sprint commit
- **Execution**: autonomous, no human checkpoint between phases
- **Date**: 2026-08-20

## 1. Scope

Visual/UX transformation toward a "smart premium residence" identity, plus a
frontend security/accessibility hardening pass — on top of an already
RC1-validated, functionally stable app. Explicitly **not** in scope: any 3D
model/Three.js/WebGL, a framework rewrite, backend/schema changes, or
anything touching production Supabase, GitHub Pages config, or secrets.

## 2. Baseline audit (before any change)

- `git diff --check`: clean. WhatsApp gateway: 9/9 tests pass. Frontend JS
  (`assets/js/*.js`): 7/7 syntax OK. Inline `<script>` blocks: 5/5 OK
  (`admin-login.html`, `admin.html`, `collecte.html`, `connexion.html`,
  `espace-proprietaire.html`). `deno check`: 5/5 Edge Functions OK.
- File inventory: 9 live HTML pages at the repo root (`index`, `inscription`,
  `collecte`, `confirmation`, `connexion`, `confidentialite`,
  `espace-proprietaire`, `admin-login`, `admin`) plus two **empty, untracked
  by any page** placeholders, `admin/login.html` and `admin/dashboard.html`
  (pre-existing, already flagged in `docs/security.md` before this sprint —
  left untouched, no clear value in touching dead scaffold).
- `assets/js/admin-auth.js`, `assets/js/dashboard.js`, `assets/js/validation.js`,
  `assets/css/admin.css` are also tracked-but-empty and referenced by
  **zero** HTML files — pre-existing dead scaffold, left untouched for the
  same reason.
- Three divergent green palettes found doing the same job: `app.css`
  (`--green-*`), `style.css` (`--primary`/`--secondary`), and
  `espace-proprietaire.html`'s inline `--mg-*` — each with slightly
  different hex values for what was conceptually the same brand green.
  `admin.html` (17,395 lines) had **no CSS custom properties at all**, ~300
  hardcoded hex colors directly in ~800 rules.

## 3. What shipped

### Design system foundation

- `assets/css/tokens.css` — canonical `--mirador-*` scale (green primary,
  anthracite ink/neutrals, a discreet gold accent with a separate
  AA-contrast-safe `-ink` variant for text use, semantic
  success/warning/danger/info, spacing/radius/shadow/motion scales),
  `prefers-reduced-motion`, global `:focus-visible`, `.sr-only`.
- `assets/css/components.css` — `.mirador-*` primitives: buttons, cards,
  badges (including a `--critical` variant for irreversible actions),
  inputs/toggle, tabs, tables, modal/drawer, toasts/alerts,
  skeleton/empty-state, and `.mirador-residence-preview` (the Sprint 2 slot,
  see §8).
- `assets/js/ui-helpers.js` (`window.MiradorUI`) — focus-trap + Escape
  helper for dialogs, `target="_blank"` hardening, reduced-motion check.
  Additive only; not yet called by existing pages (which already implement
  their own Escape/click-outside handling for their own modals — see §5).
- `app.css`, `style.css`, `espace-proprietaire.html`'s inline `--mg-*` block
  were **re-aliased** to the canonical tokens (local variable *names* kept
  untouched, only their source changed, each with a fallback matching the
  original hex) — every existing selector using those variables inherits
  the refined palette with zero selector-level changes. `form.css`'s 4
  exact brand-color literals got the same treatment directly.
- `admin.html` got a page-scoped `--adm-*` token block using **its own**
  existing dominant colors as literal values (not re-aliased to the
  slightly-different global scale) — deliberately, to avoid a visible
  two-tone seam between new/modified CSS and the ~300 untouched legacy
  color declarations in the same 17k-line file. Full migration of those
  legacy rules is explicit follow-up work, not done this sprint.
- **Adoption is honest, not uniform**: the *token* layer (CSS custom
  properties) is live on all 9 pages. The *component class* layer
  (`.mirador-btn`, `.mirador-card`, etc.) is only adopted in
  `admin-login.html` (form + button), `connexion.html` (spinners),
  `espace-proprietaire.html` (residence-preview slot), and `index.html`
  (skip link) — `admin.html` and the rest of `espace-proprietaire.html` kept
  their existing class names, recolored via tokens, rather than being
  renamed wholesale. See `docs/architecture.md` for the full breakdown.

### Auth UX (`admin-login.html`, `connexion.html`)

- Full visual pass onto the token system.
- Real loading spinners (`.mirador-spinner`) alongside the existing
  disabled-button/"..." text pattern.
- **Security fix**: both login forms rendered `error.message` from the raw
  Supabase Auth error verbatim for anything other than the exact string
  `"Invalid login credentials"` — a provider-internal message (rate limit,
  etc.) could have reached the user unfiltered. Now mapped through an
  allowlist to a safe French message, with a single generic fallback for
  anything unrecognized.
- `connexion.html` password-visibility toggles now expose `aria-pressed`.

### Owner dashboard (`espace-proprietaire.html`)

- Mobile sidebar drawer: `mobileMenuButton` now has real `aria-expanded` +
  a dynamic `aria-label`, moves focus into the drawer on open, returns
  focus to the trigger on Escape. All three close paths (nav click,
  outside click, Escape) now go through one `setSidebarOpen()` helper.
- Sidebar nav buttons: `aria-current="page"` kept in sync by `showSection()`.
- Dark-surface `:focus-visible` override (global ring has poor contrast on
  the dark sidebar background) + a subtle gold accent bar on the active
  nav item.
- Overview dashboard: the "Services de la résidence" list (5 rows + 2 more
  elsewhere) were **non-interactive `<div>`s** with a hardcoded inline
  color, reading "Actif" for every module unconditionally. Converted to
  real `<button>` quick actions (not clickable `<div>`s — a section 12/13
  requirement) wired to the same `showSection()` the sidebar already uses,
  so "Réunions/Votes/Syndic/Annonces/Documents" on the overview now
  actually navigate there.
- Added the `.mirador-residence-preview` Sprint 2 slot to the overview.
- Removed all remaining static `style="..."` attributes (status colors, ad
  hoc margins, the load-error retry button) in favor of classes. The one
  genuinely dynamic `style="width:${pct}%"` vote-result bar was left as-is
  — that value is per-instance and can't be a static class.

### Admin control center (`admin.html`)

- Admin tabs gained real ARIA tablist semantics (`role="tablist"`/`"tab"`,
  `aria-selected` kept in sync with the existing `.active` class toggle,
  `aria-controls`) — previously plain buttons with only a visual state.
- Dark header `:focus-visible` override, same rationale as the sidebar.
- Removed remaining static inline styles: 7 duplicate modal "eyebrow label"
  instances (one per modal: owner/meeting/vote/charge/payment/announcement/
  document) consolidated into one `.modal-eyebrow` class, plus 3 one-off
  margin overrides folded into existing/new classes.
- **Verified, not fixed** (already correct): destructive actions
  (`Supprimer`, `Extourner`) already carry a `.danger` class with distinct
  red styling across meetings/votes/syndic/announcements/documents, and are
  gated by a native `confirm()` prompt before the request fires. All 7
  modals already have `role="dialog"`, `aria-modal="true"`,
  `aria-labelledby`, and are already closed by one shared, generic
  `document.querySelector(".modal.visible")` Escape handler.

### `index.html` / `confidentialite.html`

Lighter touch (both were already reasonably solid, and only "if needed" per
the sprint brief): skip-to-content link, `aria-hidden` on purely decorative
icons/checkmarks (each already labeled by adjacent text), token cleanup on
`confidentialite.html`'s last two hardcoded colors. Policy text itself
untouched, per the sprint's privacy-content-preservation rule.

### `inscription.html`, `collecte.html`, `confirmation.html`

Not restructured (outside the sprint's explicit page list) — they inherit
the refined palette for free via `style.css`/`form.css`'s token aliasing,
with zero risk since neither their HTML nor JS was touched.

## 4. Security — full findings

| Severity | Finding | Status |
|---|---|---|
| MEDIUM | Auth forms leaked raw Supabase error text for non-credential failures | **Fixed** (§3, Auth UX) |
| LOW | `.residence-label`/`.residence-name` used a ~3:1-contrast gold as small bold text color (pre-existing, unchanged by the earlier token-aliasing pass — a genuine AA gap, not a regression) | **Fixed** — switched to `--mirador-gold-ink` (~5.9:1), verified by manual luminance/contrast computation, not assumed |
| — | No CSP existed at all | **Added**, Report-Only (see below) |
| — | Static inline `style="..."` scattered across the two large app pages | **Reduced** to zero except genuinely per-instance dynamic values |
| VERIFIED CLEAN | `innerHTML`/`outerHTML`/`insertAdjacentHTML`/`document.write`/`eval`/`new Function` | 50 `innerHTML` sites in `admin.html`+`espace-proprietaire.html` individually re-verified to route through `escapeHtml()` (which itself escapes `& < > " '` — all 5, not just 3); zero of the other sinks anywhere in tracked HTML/JS |
| VERIFIED CLEAN | `target="_blank"` reverse-tabnabbing | Zero occurrences exist; the 3 `window.open()` calls in the app already pass `"noopener,noreferrer"` explicitly |
| VERIFIED CLEAN | Query-parameter handling | Only one `location.search` read in the whole app (`espace-proprietaire.html`'s `?section=`), allowlist-validated before use |
| VERIFIED CLEAN | `localStorage`/`sessionStorage` | No direct `localStorage` use anywhere (Supabase SDK manages it internally via `storageKey`); `sessionStorage` only holds a temporary registration token/apartment/expiry, never a password, always cleared after use |
| VERIFIED CLEAN | Secrets in frontend code | Repo-wide grep for `service_role`, `sk_live`/`sk_test`, private-key markers: nothing. `services/whatsapp-gateway/.env` and `.wa-auth/` confirmed still untracked |
| VERIFIED CLEAN | Console logging | Every `console.error`/`.warn` call logs a generic `Error` object with a descriptive label, never a raw password/token/session/phone/email value |
| VERIFIED CLEAN | Auth fail-closed ordering | `admin.html`'s first data fetch (`loadOwners()`) awaits `requireAdmin()` and returns before any query if it fails, so sensitive data can never reach the DOM ahead of the check; `espace-proprietaire.html` correctly distinguishes "no session" (redirect) from "network error checking session" (show error, keep session — does **not** grant access, does **not** force logout on a transient blip) |

Content-Security-Policy: added as `Content-Security-Policy-Report-Only` on
all 9 pages, with a per-page allowlist derived from an actual audit of what
each page loads (not a copy-pasted blanket policy — see the table in
`docs/security.md`). Deliberately **not enforcing**: this sprint had no
browser automation available to verify a blocking policy doesn't silently
break login/dashboard for every user, and that risk was judged
disproportionate to push unverified. `frame-ancestors` is documented as a
target but not set — it requires a real HTTP header, which GitHub Pages
static hosting cannot send via `<meta>`.

New CI guard (`.github/scripts/check-frontend-security.js`): every
`target="_blank"` has `rel="noopener noreferrer"`, no
`document.write`/`eval`/`new Function`/`javascript:` URL anywhere, every
non-empty page has a CSP meta tag. Runs clean today (9/9 real pages OK, 2
known-empty placeholders correctly skipped).

## 5. Accessibility — full findings

- Admin tabs: added `role="tablist"`/`"tab"`/`aria-selected`/`aria-controls`
  (previously plain buttons with only visual state).
- Owner sidebar nav: added `aria-current="page"`.
- Mobile menu button (owner dashboard): added `aria-expanded`, dynamic
  `aria-label`, focus-in-on-open, focus-return-on-Escape.
- Dark-surface `:focus-visible` overrides on both dark headers (admin
  header, owner sidebar) — the global green ring is low-contrast there.
- Password-visibility toggles (`connexion.html`): `aria-pressed`.
- Decorative icons/checkmarks: `aria-hidden="true"` where an adjacent
  label already conveys the meaning (`index.html`).
- Skip-to-content link added to `index.html`.
- `reduced-motion`: handled once, globally, in `tokens.css`
  (`@media (prefers-reduced-motion: reduce)` forces near-zero animation/
  transition duration everywhere the stylesheet loads); new animations in
  `components.css` (skeleton shimmer, spinner, modal/drawer rise) are
  additionally gated behind `@media (prefers-reduced-motion: no-preference)`
  — opt-in rather than opt-out.
- Gold-text contrast fix — see §4.
- `type="button"` audit: counted `<button>` tags vs. explicit `type=`
  attributes across every heavily-edited file — 100% match everywhere
  (73/73 in `admin.html`, 37/37 in `espace-proprietaire.html`, etc.). No
  accidental-submit risk found.
- **Verified, not changed**: all 7 admin modals already had
  `role="dialog"`, `aria-modal="true"`, `aria-labelledby`, and a shared
  Escape-to-close handler before this sprint.
- **Not done**: a full keyboard focus-trap for the owner dashboard's mobile
  drawer (the `ui-helpers.js` `trapFocus()` helper exists and is ready, but
  wasn't wired in — Escape-to-close and click-outside-to-close already
  provide an exit path, and trapping focus across 4 code paths without a
  real browser to verify felt like a worse risk/value trade than leaving it
  as documented follow-up).

## 6. Responsive / mobile

Static-analysis-only (no browser available — see §9):

- No horizontal-overflow risk introduced: new components
  (`.mirador-modal`, `.mirador-toast-region`) use relative/`min()`/`calc()`
  sizing; `.mirador-table` sits inside an `overflow-x: auto` wrapper
  (scrolls instead of breaking); `admin.html`'s tab bar already used
  `flex-wrap` (wraps instead of overflowing) — left as-is.
- Existing breakpoints (`connexion.html`: 900px/520px;
  `espace-proprietaire.html`: 860px; `admin.html`: unchanged) were not
  touched, only the colors/tokens inside them.
- Touch targets: buttons/inputs already ≥44px min-height across edited
  forms; the new (not-yet-adopted) `.mirador-toggle` is 44×26px, which
  clears WCAG 2.2's 24×24px AA minimum (checked against the actual
  criterion rather than assumed from the stricter 44×44 AAA guideline).
- **MANUAL BROWSER TEST REQUIRED** for actual rendering at 320/375/390/
  430/768/1024/1440px — no claim of a visual PASS is made here; see §9.

## 7. Performance

- New CSS/JS weight: `tokens.css` (5.1KB) + `components.css` (16.5KB) +
  `ui-helpers.js` (4.0KB) ≈ 25.5KB uncompressed, unminified, loaded once
  and cached — no framework, no new external dependency, no build step
  introduced.
- Duplicate-listener check after refactoring the sidebar/tab-button click
  handlers: `mobileMenuButton.addEventListener` and each admin
  `*TabButton.addEventListener` still appear exactly once each — confirmed
  via grep, not assumed.
- No new `backdrop-filter`/blur heavier than what already existed
  (`.mirador-overlay` uses a light 3px blur; the app already had 12–14px
  blurs on its nav bars before this sprint).
- Sprint 2 3D readiness: `.mirador-residence-preview` is pure CSS/HTML
  today — zero JS, zero image/model assets, zero third-party dependency.
  The initial page load of every page is fully independent of any future
  3D work. See `docs/architecture.md` for the specific lazy-load/
  capability-detection/fallback plan documented for Sprint 2.

## 8. Sprint 2 (3D) hand-off

No Three.js/WebGL/GLB — as mandated. What's ready:

- A named, styled, responsive slot (`.mirador-residence-preview`, with
  `--loading`/`--unsupported` modifier classes already defined) live today
  in the owner dashboard overview.
- A documented plan in `docs/architecture.md` (§"Résidence 3D") for
  capability detection, lazy-loading, loading/unsupported states, and the
  2D fallback — written so Sprint 2 can implement against it without
  re-deriving the integration points.
- The design token scale (spacing/radius/shadow/motion) Sprint 2's UI
  chrome around the 3D canvas can reuse directly.

## 9. Tests

Baseline (before any change) and final (after all commits) — both runs
shown so a regression between them would be visible:

| Check | Baseline | Final |
|---|---|---|
| `git diff --check` | PASS | PASS |
| WhatsApp gateway (`npm test`) | 9/9 PASS | 9/9 PASS |
| `assets/js/*.js` (`node --check`) | 7/7 PASS | 7/7 PASS |
| Inline `<script>` blocks | 5/5 PASS | 5/5 PASS |
| Edge Functions (`deno check`) | 5/5 PASS | 5/5 PASS |
| `check-frontend-security.js` (new) | n/a | 9/9 PASS (2 empty files correctly skipped) |
| Secret scan | n/a | NOT FOUND (service_role, sk_live/test, private keys, `.env`/`.wa-auth` confirmed untracked) |

**BROWSER E2E = NOT EXECUTED.** No browser automation (Playwright or
otherwise) was available in this environment. Every claim in this document
about actual rendering, click-through flows, or visual appearance is
derived from reading code, not from observing a running page — stated
explicitly rather than implied as tested.

## 10. Functional regression status

No business logic, Supabase calls, RLS-dependent queries, or
data-fetching functions were modified — every edit in this sprint is CSS
(colors/spacing/tokens), HTML structure (classes, ARIA attributes, one
`<div>`→`<button>` conversion per quick-action row), or narrowly-scoped
JS (error-message mapping, `aria-*` attribute sync, a `setSidebarOpen()`
refactor that preserves all three original call sites). Given that:

| Flow | Status | Basis |
|---|---|---|
| Admin login | PASS (static) | Auth call unchanged; only error-display path touched, syntax-checked |
| Owner login/activation | PASS (static) | Same |
| Admin dashboard load / tabs | PASS (static) | `showAdminSection()` logic unchanged, only `aria-*` sync added |
| Owner dashboard load / sections | PASS (static) | `showSection()` logic unchanged, only `aria-*`/focus sync added |
| Réunions/Votes/Syndic/Annonces/Documents (admin) | PASS (static) | No CRUD/query code touched |
| Réunions/Votes/Syndic/Annonces/Documents (owner) | PASS (static) | Same; overview quick-actions call the pre-existing `showSection()` |
| Notifications | PASS (static) | Not touched |
| Logout (both) | PASS (static) | Not touched |
| Actual rendered UI, click-through, visual regressions | NOT TESTED | No browser available — see §9 |

"PASS (static)" means: syntax-checked, logic traced by reading the code,
and confirmed the specific lines that changed don't touch the function
being described. It is **not** a claim of having run the app.

## 11. Cleanup

No debug `console.log`/`TODO`/`FIXME`/`debugger` statements were introduced
(checked the full sprint diff, not just spot-checked). Legacy `console.error`
calls were left as-is (pre-existing, not sprint scope). The unused
`.mirador-*` component classes not yet adopted into any page
(`.mirador-card`, `.mirador-badge`, `.mirador-tabs`, `.mirador-table`,
`.mirador-modal`, `.mirador-toggle`, `.mirador-drawer`, `.mirador-alert`)
are intentional library primitives — the explicit "design system
foundation" deliverable — not dead code, and are documented as such in
`docs/architecture.md` rather than removed.

## 12. Known limitations / explicit follow-up

- `admin.html`'s ~300 pre-existing hardcoded colors were not migrated to
  the shared token scale (§3) — proportionate risk call, not an oversight.
- CSP is Report-Only everywhere, pending a manual browser check (§4).
- `.mirador-*` component-class adoption is partial (§3) — the library is
  ready for broader adoption in a follow-up pass.
- Mobile drawer focus-trap not wired in (§5) — helper exists, not applied.
- No browser/E2E testing was performed at any point (§9) — this is the
  single biggest gap between "code review passed" and "verified working."

## 13. Manual browser validation required

Before this branch is trusted beyond code review, a human needs to, in an
actual browser:

1. Open each of the 9 pages and confirm zero `Content-Security-Policy`
   violations in DevTools console, then flip each page's meta tag from
   `-Report-Only` to enforcing.
2. Click through: admin login → dashboard → each tab; owner login/
   activation → dashboard → each sidebar section → each new overview
   quick-action button → mobile hamburger menu (open/close/Escape/
   outside-click) → logout (both roles).
3. Resize/device-test at 320, 375, 390, 430, 768, 1024, 1440px — confirm
   no horizontal overflow, no clipped modals, no unreadable text.
4. Verify the visual design actually reads as "premium residence" and not
   just "recolored" — this is inherently a visual judgment call no static
   check can make.
5. Confirm the new focus rings, `aria-current`/`aria-selected`/
   `aria-expanded` states behave correctly with a real screen reader
   (NVDA/VoiceOver) and keyboard-only navigation.
