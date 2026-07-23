# Noura — Food Discovery Platform

Discover restaurants, get AI-powered recipe help, and connect with local food vendors across Nigeria and Africa.

## Structure

Five standalone HTML files (no build step, no bundler) — each is self-contained with its own inlined config/services/app logic:

| File | What it is |
|---|---|
| `landing.html` | Public marketing/waitlist page |
| `index.html` | Main consumer app |
| `vendor.html` | Vendor portal (business dashboard) |
| `admin.html` | Internal admin dashboard — **do not link publicly** |
| `store.html` | Public vendor storefront pages (`store.html?v=vendor-slug`) |
| `noura-legal.html` | Privacy Policy, Terms of Service, Mission, Values |

Supporting files:
- `config.js`, `services.js` — reference copies of what's inlined in each HTML file (edit these, then re-inline — see below)
- `manifest.json`, `sw.js` — PWA install support
- `supabase/` — database schema, Edge Functions, and setup docs for your backend

## Deploying to Vercel

No build step needed. Connect the repo, framework preset **"Other"**, output directory = repo root. Vercel will serve the HTML files directly.

## Before you push — checklist

- [x] PWA icons generated from your logo — `icons/`, `favicon.png`, `apple-touch-icon.png`, `og-image.jpg`
- [x] Real admin moderation actions (approve/suspend vendors, delete reviews/meals/restaurants, see real users)
- [x] Legal pages (`noura-legal.html`) — Privacy, Terms, Mission, Values. **Have a lawyer review before relying on this for a public commercial launch — it's a real, honest starting point, not legal advice.**
- [x] AI rate limiting — per-user and platform-wide daily caps protect the shared Gemini free tier
- [ ] Set a real `ADMIN_API_KEY` in `config.js` (currently a placeholder) and match it in Supabase secrets
- [ ] Confirm `SUPABASE_URL` / `SUPABASE_ANON_KEY` in `config.js` match your project
- [ ] Deploy all 3 Edge Functions (`gemini-chat`, `admin-challenges`, `admin-actions`) and set their secrets
- [ ] Run all SQL files in `supabase/` in this order:
  1. `schema.sql`
  2. `auth_trigger.sql`
  3. `challenges_table.sql`
  4. `storage_setup.sql`
  5. `vendor_policies.sql`
  6. `admin_moderation_columns.sql`
  7. `ai_rate_limit_table.sql`
- [ ] Don't link `admin.html` anywhere public-facing
- [ ] **Click through the whole app yourself in a real browser before announcing it publicly.** Everything here has been verified statically (syntax checks, function-coverage sweeps) — that catches broken code, not broken UX.

## Two separate installable apps

`index.html` (consumer) and `vendor.html` (business) are each their own PWA — separate `manifest.json`/`manifest-vendor.json`, separate `sw.js`/`sw-vendor.js`, separate install prompts. Installing one doesn't install or affect the other. Both currently share the same icon artwork (from your logo) — swap in a distinct business icon later if you want them visually distinguishable on a home screen.

## Editing after inlining

Each HTML file has `config.js`/`services.js`/app-logic inlined directly in `<script>` tags (kept this way deliberately — external `<script src>` files don't reliably load when opened via `file://`, which matters for phone-based testing). If you edit `config.js` or `services.js`, those changes need to be re-copied into every HTML file's inlined copy to stay in sync — they will NOT auto-update.
