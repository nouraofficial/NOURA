/**
 * ══════════════════════════════════════════════════════════════
 *  NOURA — ENVIRONMENT CONFIG
 * ══════════════════════════════════════════════════════════════
 *  Single source of truth for every URL, key, and environment
 *  flag used by the app. No other file should hardcode a URL
 *  or a key — everything reads from window.NOURA_ENV.
 *
 *  ⚠️ IMPORTANT — READ THIS BEFORE DEPLOYING:
 *  This is a static HTML app with no build/server step, so
 *  ANYTHING in this file ships to and is visible in the user's
 *  browser (view-source, DevTools, etc.) — that's true no matter
 *  whether it's inlined or loaded from a separate .js file.
 *  A real .env file only stays secret because a SERVER reads it;
 *  a static site has no server, so nothing here can be truly
 *  hidden. What we CAN do — and this file does — is:
 *    1. Keep every key in exactly one place, matching real .env
 *       variable names, so swapping to a real backend later is
 *       a 1:1 copy-paste, not a rewrite.
 *    2. Never commit REAL key values to GitHub — only ever
 *       commit this file with the placeholder values below.
 *       Paste your real keys only into the copy you deploy.
 *    3. Separate keys that are safe to expose (below, marked
 *       PUBLIC) from ones that are billing/abuse-sensitive
 *       (marked SENSITIVE) — those should move behind a backend
 *       proxy (Supabase Edge Function) as soon as one exists,
 *       instead of staying in client-side code long-term.
 *
 *  See .env.example (same folder) for the copy-pasteable list.
 * ══════════════════════════════════════════════════════════════
 */
window.NOURA_ENV = {
  // ── Environment ────────────────────────────────────────────
  ENVIRONMENT: 'development', // 'development' | 'staging' | 'production'
  APP_VERSION: '1.0.0-month1',

  // ── Backend API (Supabase Edge Functions — Month 2) ─────────
  // PUBLIC. Leave BACKEND_READY = false until the real API exists.
  BACKEND_READY: false,
  API_BASE_URL: '', // e.g. 'https://xyzcompany.functions.supabase.co'

  // ── Supabase ─────────────────────────────────────────────────
  // PUBLIC — Supabase's anon key is designed to be exposed
  // client-side; real access control happens via Row Level
  // Security policies on the backend, not by hiding this key.
  SUPABASE_URL: 'https://qkuznrnxclppvorpomcr.supabase.co',
  SUPABASE_ANON_KEY: 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InFrdXpucm54Y2xwcHZvcnBvbWNyIiwicm9sZSI6ImFub24iLCJpYXQiOjE3ODQ1NzU3NDcsImV4cCI6MjEwMDE1MTc0N30.FFtuXBaH1NhJQeockvXsCDfCsZcP2AT6B51O9yXJS_0',

  // ── Admin-only actions (challenge creation, etc.) ────────────
  // ⚠️ Must exactly match the ADMIN_API_KEY secret you set in
  // Supabase → Edge Functions → Secrets. This is a stopgap for a
  // single-admin MVP, not real per-account admin permissions —
  // anyone with this value (visible in admin.html's source) can
  // call admin actions, so treat admin.html itself as something
  // you don't publicly link/index, not just this key as protection.
  ADMIN_API_KEY: 'Jhsrolnfd3866hnspos93b3blkwhs',

  // ── Google OAuth ─────────────────────────────────────────────
  // PUBLIC — OAuth client IDs are meant to be public.
  GOOGLE_CLIENT_ID: '',

  // ── Recipe data providers ─────────────────────────────────────
  // PUBLIC. TheMealDB needs no key. Edamam's free-tier app ID/key
  // are rate-limited per key, not billed — safe enough client-side
  // for now. Get free keys at https://developer.edamam.com
  MEALDB_BASE_URL: 'https://www.themealdb.com/api/json/v1/1',
  EDAMAM_APP_ID: 'YOUR_EDAMAM_APP_ID',
  EDAMAM_APP_KEY: 'YOUR_EDAMAM_APP_KEY',

  // ── AI provider (Noura AI chat + recipe generation) ──────────
  // ⚠️ SENSITIVE — this key is billed per request. Anyone who
  // views this page's source can copy it and run up your bill.
  // Fine for early testing; before real launch, move Gemini calls
  // behind a Supabase Edge Function so this key never reaches the
  // browser (see /supabase/functions/gemini-chat). Get a free key
  // at https://aistudio.google.com
  GEMINI_API_KEY: 'YOUR_GEMINI_KEY_HERE',
  GEMINI_MODEL: 'gemini-flash-latest', // alias — always resolves to current model, avoids future 404s

  // ── CORS proxies (dev-only fallback for local file:// testing) ─
  DEV_CORS_PROXIES: [
    (u) => 'https://corsproxy.io/?' + encodeURIComponent(u),
    (u) => 'https://api.allorigins.win/raw?url=' + encodeURIComponent(u),
  ],
};

