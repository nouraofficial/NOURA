import { createClient } from 'https://esm.sh/@supabase/supabase-js@2';

const cors = {
  'Access-Control-Allow-Origin': '*',
  'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type, x-admin-key',
  'Access-Control-Allow-Methods': 'POST, OPTIONS',
};

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), { status, headers: { ...cors, 'Content-Type': 'application/json' } });

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') return new Response('ok', { headers: cors });
  if (req.method !== 'POST') return json({ ok: false, error: 'method_not_allowed' }, 405);

  const adminKey = req.headers.get('x-admin-key');
  const expected = Deno.env.get('ADMIN_API_KEY');
  if (!adminKey || !expected || adminKey !== expected) return json({ ok: false, error: 'unauthorized' }, 401);

  const url = Deno.env.get('SUPABASE_URL');
  const serviceKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
  if (!url || !serviceKey) return json({ ok: false, error: 'server_not_configured' }, 500);

  const db = createClient(url, serviceKey, { auth: { persistSession: false } });
  const { action, payload = {} } = await req.json().catch(() => ({ action: '', payload: {} }));
  const adminId = req.headers.get('x-admin-id') || 'admin@noura.app';

  try {
    if (action === 'list_posts') {
      const { data, error } = await db.from('community_posts').select('*').order('created_at', { ascending: false }).limit(200);
      if (error) throw error;
      return json({ ok: true, posts: data || [] });
    }

    if (action === 'list_reports') {
      const { data, error } = await db.from('community_reports').select('*').order('created_at', { ascending: false }).limit(200);
      if (error) throw error;
      return json({ ok: true, reports: data || [] });
    }

    if (action === 'stats') {
      const [posts, reports, campuses, users] = await Promise.all([
        db.from('community_posts').select('*', { count: 'exact', head: true }).eq('status', 'published'),
        db.from('community_reports').select('*', { count: 'exact', head: true }).eq('status', 'open'),
        db.from('campuses').select('*', { count: 'exact', head: true }).eq('is_active', true),
        db.from('community_profiles').select('*', { count: 'exact', head: true }),
      ]);
      return json({ ok: true, stats: { posts: posts.count || 0, reports: reports.count || 0, campuses: campuses.count || 0, users: users.count || 0 } });
    }

    if (action === 'hide_post' || action === 'publish_post') {
      const status = action === 'hide_post' ? 'hidden' : 'published';
      const { error } = await db.from('community_posts').update({ status, hidden_reason: status === 'hidden' ? 'Hidden by Noura moderation' : null }).eq('id', payload.postId);
      if (error) throw error;
      await db.from('community_moderation_actions').insert({ admin_id: adminId, action, target_type: 'post', target_id: payload.postId, reason: payload.reason || null });
      return json({ ok: true });
    }

    if (action === 'delete_post') {
      const { error } = await db.from('community_posts').delete().eq('id', payload.postId);
      if (error) throw error;
      await db.from('community_moderation_actions').insert({ admin_id: adminId, action, target_type: 'post', target_id: payload.postId, reason: payload.reason || null });
      return json({ ok: true });
    }

    if (action === 'resolve_report') {
      const { error } = await db.from('community_reports').update({ status: 'resolved', resolved_by: adminId, resolved_at: new Date().toISOString(), moderator_note: payload.note || null }).eq('id', payload.reportId);
      if (error) throw error;
      await db.from('community_moderation_actions').insert({ admin_id: adminId, action, target_type: 'report', target_id: payload.reportId, reason: payload.note || null });
      return json({ ok: true });
    }

    if (action === 'set_user_status') {
      const allowed = ['active', 'limited', 'suspended', 'banned'];
      if (!allowed.includes(payload.status)) return json({ ok: false, error: 'invalid_status' }, 400);
      const { error } = await db.from('community_user_status').upsert({ user_id: payload.userId, status: payload.status, reason: payload.reason || null, expires_at: payload.expiresAt || null, updated_by: adminId, updated_at: new Date().toISOString() });
      if (error) throw error;
      await db.from('community_moderation_actions').insert({ admin_id: adminId, action, target_type: 'user', target_id: payload.userId, reason: payload.reason || null });
      return json({ ok: true });
    }

    if (action === 'official_post') {
      const { data: official, error: officialError } = await db.from('noura_official_account').select('*').eq('username', '@noura').maybeSingle();
      if (officialError) throw officialError;
      if (!official) return json({ ok: false, error: 'official_account_missing' }, 500);
      const title = String(payload.title || '').trim();
      const body = String(payload.body || '').trim();
      if (!body) return json({ ok: false, error: 'empty_body' }, 400);
      const text = title ? `📢 ${title}\n\n${body}` : `📢 ${body}`;
      const { data, error } = await db.from('community_posts').insert({
        author_id: official.id,
        author_name: official.display_name,
        author_username: official.username,
        author_avatar_url: official.avatar_url,
        author_is_official: true,
        is_official: true,
        campus_id: payload.campusId || null,
        status: 'published',
        post_type: 'post',
        body: text,
      }).select('*').single();
      if (error) throw error;
      await db.from('community_moderation_actions').insert({ admin_id: adminId, action, target_type: 'official_post', target_id: data.id, reason: title || null });
      return json({ ok: true, post: data });
    }

    return json({ ok: false, error: 'unknown_action' }, 400);
  } catch (error) {
    console.error(error);
    return json({ ok: false, error: error?.message || 'server_error' }, 500);
  }
});
