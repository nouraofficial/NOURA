// ══════════════════════════════════════════════════════════════
//  gemini-chat — Supabase Edge Function
// ══════════════════════════════════════════════════════════════
//  Proxies Noura AI chat requests to Gemini. The Gemini key lives
//  ONLY in Supabase's server-side secrets (never in the browser).
//  Now includes real rate limiting — per-user and platform-wide
//  daily caps — so one heavy user (or abuse) can't exhaust the
//  shared free-tier quota for everyone else.
//
//  Deploy:
//    supabase functions deploy gemini-chat
//    supabase secrets set GEMINI_API_KEY=your_real_key_here
//    (SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY are already
//     available automatically inside every Edge Function)
//
//  Call from the frontend (see aiService.chat in services.js):
//    POST {SUPABASE_URL}/functions/v1/gemini-chat
//    body: { history: [...], systemPrompt: "..." }
//    header: Authorization: Bearer {SUPABASE_ANON_KEY or user JWT}
// ══════════════════════════════════════════════════════════════

import { serve } from "https://deno.land/std@0.203.0/http/server.ts";
import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const GEMINI_MODEL = "gemini-flash-latest";
const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*", // tighten to your real domain before launch
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

// Tune these against your actual Gemini free-tier daily quota.
// Kept conservative so there's headroom even on a busy day.
const PER_USER_DAILY_LIMIT = 20;
const ANONYMOUS_DAILY_LIMIT = 5; // stricter — no logged-in user to attribute abuse to
const GLOBAL_DAILY_LIMIT = 200;

serve(async (req) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: CORS_HEADERS });

  try {
    const { history, systemPrompt } = await req.json();
    const apiKey = Deno.env.get("GEMINI_API_KEY");

    if (!apiKey) return json({ ok: false, error: "server_not_configured" }, 500);
    if (!Array.isArray(history) || !history.length) return json({ ok: false, error: "missing_history" }, 400);

    const supabase = createClient(
      Deno.env.get("SUPABASE_URL")!,
      Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!
    );

    // Identify the caller (if logged in) so limits are per-account, not just per-request.
    let userId: string | null = null;
    const authHeader = req.headers.get("authorization");
    if (authHeader) {
      const token = authHeader.replace("Bearer ", "");
      const { data } = await supabase.auth.getUser(token);
      userId = data?.user?.id || null;
    }

    const since = new Date(Date.now() - 24 * 60 * 60 * 1000).toISOString();

    // Platform-wide cap — protects the shared quota no matter who's asking.
    const { count: globalCount } = await supabase
      .from("ai_usage_log").select("id", { count: "exact", head: true }).gte("created_at", since);
    if ((globalCount || 0) >= GLOBAL_DAILY_LIMIT) {
      return json({ ok: false, error: "rate_limited", text: "🙏 Noura AI has hit its daily limit across all users — please try again tomorrow." }, 429);
    }

    // Per-caller cap.
    let callerCount = 0;
    if (userId) {
      const { count } = await supabase.from("ai_usage_log").select("id", { count: "exact", head: true }).eq("user_id", userId).gte("created_at", since);
      callerCount = count || 0;
      if (callerCount >= PER_USER_DAILY_LIMIT) {
        return json({ ok: false, error: "rate_limited", text: `🙏 You've hit today's AI chat limit (${PER_USER_DAILY_LIMIT} messages). Try again tomorrow!` }, 429);
      }
    } else {
      const { count } = await supabase.from("ai_usage_log").select("id", { count: "exact", head: true }).is("user_id", null).gte("created_at", since);
      callerCount = count || 0;
      if (callerCount >= ANONYMOUS_DAILY_LIMIT) {
        return json({ ok: false, error: "rate_limited", text: "🙏 You've hit today's AI chat limit for guests — log in for more, or try again tomorrow!" }, 429);
      }
    }

    const url = `https://generativelanguage.googleapis.com/v1beta/models/${GEMINI_MODEL}:generateContent?key=${apiKey}`;
    const body = {
      system_instruction: { parts: [{ text: systemPrompt || "You are Noura AI, a helpful food assistant." }] },
      contents: history.slice(-20),
      generationConfig: { temperature: 0.85, maxOutputTokens: 400 },
    };

    const startedAt = Date.now();
    const res = await fetch(url, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });

    // Log the attempt regardless of outcome — failed calls still count
    // against the caller's cap to prevent retry-spam from bypassing it.
    await supabase.from("ai_usage_log").insert({ user_id: userId });

    if (!res.ok) return json({ ok: false, error: "gemini_error", status: res.status }, 502);

    const data = await res.json();
    const reply = data.candidates?.[0]?.content?.parts?.[0]?.text || "Sorry, try again!";

    return json({ ok: true, text: reply, ms: Date.now() - startedAt });
  } catch (err) {
    return json({ ok: false, error: "network", message: String(err) }, 500);
  }
});

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { ...CORS_HEADERS, "Content-Type": "application/json" } });
}
