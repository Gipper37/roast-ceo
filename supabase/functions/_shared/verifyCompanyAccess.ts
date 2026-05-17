// Shared helper for edge functions that accept a company_id and need
// to confirm the caller actually belongs to that company.
//
// Why this exists:
//   Edge functions are exposed at <SUPABASE_URL>/functions/v1/<name>
//   and accept any payload. Without explicit verification, anyone
//   discovering the URL could POST a company_id they don't own and
//   trigger privileged operations (e.g. spin up Stripe checkout/portal
//   sessions for someone else's company).
//
// How:
//   1. Caller must pass `Authorization: Bearer <user_jwt>` — the JWT
//      Supabase issues to authenticated users.
//   2. We instantiate an anon supabase client + ask it auth.getUser()
//      with the JWT. If invalid → 401.
//   3. We look up the team table with service_role to find the user's
//      company_ids (an auth user can belong to multiple).
//   4. We confirm the requested company_id is in that set.
//
// Returns { user, team } on success, or a Response object to return.

// eslint-disable-next-line @typescript-eslint/triple-slash-reference
/// <reference lib="deno.ns" />
import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import { corsHeaders } from './cors.ts'

export type CallerInfo = {
  user_id: string
  email: string | null
  team_company_ids: string[]
}

export async function verifyCompanyAccess(
  req: Request,
  required_company_id: string,
): Promise<{ ok: true; caller: CallerInfo } | { ok: false; response: Response }> {
  const auth = req.headers.get('Authorization') || ''
  const token = auth.startsWith('Bearer ') ? auth.slice(7) : ''
  if (!token) {
    return { ok: false, response: jsonErr('Missing Authorization header', 401) }
  }

  // Anon client to validate the user's JWT
  const sbAnon = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_ANON_KEY')!,
    { global: { headers: { Authorization: `Bearer ${token}` } } },
  )
  const { data: userData, error: userErr } = await sbAnon.auth.getUser(token)
  if (userErr || !userData?.user) {
    return { ok: false, response: jsonErr('Invalid or expired token', 401) }
  }
  const user = userData.user

  // Service-role client to look up team rows (bypasses RLS — necessary
  // because the user may not yet have established their tenant context).
  const sbAdmin = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } },
  )

  const { data: teamRows, error: teamErr } = await sbAdmin
    .from('team')
    .select('company_id')
    .eq('auth_user_id', user.id)
    .eq('is_active', true)

  if (teamErr) {
    return { ok: false, response: jsonErr('Team lookup failed', 500) }
  }

  const company_ids = (teamRows || []).map((t: { company_id: string }) => t.company_id)
  if (!company_ids.includes(required_company_id)) {
    return { ok: false, response: jsonErr('You do not have access to this company', 403) }
  }

  return {
    ok: true,
    caller: {
      user_id: user.id,
      email: user.email ?? null,
      team_company_ids: company_ids,
    },
  }
}

function jsonErr(message: string, status: number): Response {
  return new Response(JSON.stringify({ error: message }), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
