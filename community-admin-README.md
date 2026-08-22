# Noura Community Admin Edge Function

Deploy as `community-admin` and set these Supabase Edge Function secrets:

- `SUPABASE_SERVICE_ROLE_KEY`
- `ADMIN_API_KEY` — must match the value used by `admin.html`

This function handles moderation and the official Noura account. Do not expose the service-role key to the browser.
