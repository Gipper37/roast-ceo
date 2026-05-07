import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14?target=deno'
import { corsHeaders } from '../_shared/cors.ts'

// Parameter ID map: friendly key → standard_parameters.parameters_id
const PARAM_ID_MAP: Record<string, string> = {
  retention_rate:   '1de271df',
  charge_weight:    '761fd894',
  roast_reset_day:  'RF1iFWjOh7',
  orders_reset_day: 'orders_reset_day',
  units:            'units',
}

const TRIAL_DAYS = 30

function welcomeEmailHtml(adminName: string, companyName: string, trialDays: number): string {
  const firstName = adminName.split(' ')[0]
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>Welcome to STRATA</title>
</head>
<body style="margin:0;padding:0;background:#f4f4f0;font-family:'Helvetica Neue',Helvetica,Arial,sans-serif;">
  <table width="100%" cellpadding="0" cellspacing="0" style="background:#f4f4f0;padding:40px 0;">
    <tr>
      <td align="center">
        <table width="540" cellpadding="0" cellspacing="0" style="background:#ffffff;border-radius:8px;overflow:hidden;box-shadow:0 1px 4px rgba(0,0,0,0.08);">
          <!-- Header -->
          <tr>
            <td style="background:#ffffff;padding:28px 40px 20px;text-align:center;">
              <img src="https://pwpslalerytymorcodlv.supabase.co/storage/v1/object/public/Branding/STRATA%20Full%20Logo%20-%20150ppi.png" alt="STRATA" width="180" style="display:block;margin:0 auto;" />
              <p style="margin:8px 0 0;font-size:11px;letter-spacing:2px;text-transform:uppercase;color:#999999;">Roaster Operating System</p>
            </td>
          </tr>
          <!-- Body -->
          <tr>
            <td style="padding:40px 40px 32px;">
              <h1 style="margin:0 0 16px;font-size:22px;font-weight:700;color:#1a1a1a;">Welcome to STRATA, ${firstName}!</h1>
              <p style="margin:0 0 16px;font-size:15px;line-height:1.6;color:#555555;">
                Your account for <strong>${companyName}</strong> is ready and your ${trialDays}-day free trial has started.
              </p>
              <p style="margin:0 0 24px;font-size:15px;line-height:1.6;color:#555555;">
                Log in to set up your products, recipes, and start tracking your roasts.
              </p>
              <table cellpadding="0" cellspacing="0">
                <tr>
                  <td style="border-radius:6px;background:#3D1A00;">
                    <a href="https://strataroast.com/login" style="display:inline-block;padding:14px 32px;color:#ffffff;font-size:14px;font-weight:600;text-decoration:none;border-radius:6px;">
                      Log In to STRATA
                    </a>
                  </td>
                </tr>
              </table>
              <p style="margin:24px 0 0;font-size:13px;color:#999999;">
                If you have any questions, just reply to this email. We're here to help.
              </p>
            </td>
          </tr>
          <!-- Footer -->
          <tr>
            <td style="padding:20px 40px;border-top:1px solid #eeeeee;text-align:center;">
              <p style="margin:0;font-size:12px;color:#aaaaaa;">&copy; 2026 STRATA &mdash; Built by roasters, for roasters.</p>
            </td>
          </tr>
        </table>
      </td>
    </tr>
  </table>
</body>
</html>`
}

Deno.serve(async (req) => {
  // Handle CORS preflight
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  if (req.method !== 'POST') {
    return json({ error: 'Method not allowed' }, 405)
  }

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
    apiVersion: '2024-06-20',
    httpClient: Stripe.createFetchHttpClient(),
  })

  let body: Record<string, unknown>
  try {
    body = await req.json()
  } catch {
    return json({ error: 'Invalid JSON body' }, 400)
  }

  const {
    company_name,
    facility_name,
    country_code,
    timezone,
    admin_name,
    email,
    password,
    plan_id = 'starter',
    billing_interval = 'monthly',
    parameters = {},
  } = body as {
    company_name:     string
    facility_name:    string
    country_code?:    string
    timezone:         string
    admin_name:       string
    email:            string
    password:         string
    plan_id?:         string
    billing_interval?: string
    parameters?:      Record<string, string | number>
  }

  // ── Validate required fields ───────────────────────────────────────────────
  const missing = ['company_name', 'facility_name', 'timezone', 'admin_name', 'email', 'password']
    .filter(f => !body[f])
  if (missing.length) {
    return json({ error: `Missing required fields: ${missing.join(', ')}` }, 400)
  }

  // ── Step 1: Create Supabase Auth user ─────────────────────────────────────
  const { data: authData, error: authError } = await supabase.auth.admin.createUser({
    email,
    password,
    email_confirm: true,  // auto-confirm; welcome email sent separately via Resend
  })

  if (authError) {
    return json({ error: authError.message }, 400)
  }

  const authUserId = authData.user.id

  // IDs declared outside try so the catch block can clean them up
  let companyId        = ''
  let facilityId       = ''
  let teamMemberId     = ''
  let stripeCustomerId = ''
  let subscriptionId   = ''

  try {
    companyId    = crypto.randomUUID()
    facilityId   = crypto.randomUUID()
    teamMemberId = crypto.randomUUID()

    // 2. Insert company (stripe_customer_id filled in after Stripe customer created)
    const { error: companyErr } = await supabase
      .from('companies')
      .insert({ company_id: companyId, company_name, created_by: teamMemberId })
    if (companyErr) throw companyErr

    // 3. Insert facility
    const { error: facilityErr } = await supabase
      .from('facilities')
      .insert({
        facility_id:   facilityId,
        company_id:    companyId,
        facility_name,
        time_zone:     timezone,
        country_code:  country_code ?? null,
        created_by:    teamMemberId,
      })
    if (facilityErr) throw facilityErr

    // 4. Insert team member (company admin)
    const { error: teamErr } = await supabase
      .from('team')
      .insert({
        team_member_id: teamMemberId,
        name:           admin_name,
        email,
        company_id:     companyId,
        facility_id:    facilityId,
        role:           'company_admin',
        auth_user_id:   authUserId,
        created_by:     teamMemberId,
      })
    if (teamErr) throw teamErr

    // 5. Seed company_parameters from standard_parameters
    const { data: stdParams, error: stdParamsErr } = await supabase
      .from('standard_parameters')
      .select('parameters_id, text_value, amount, data_type, parameter')
    if (stdParamsErr) throw stdParamsErr

    // Build a mutable map of parameter values for easy override
    const paramValues: Record<string, { value: string | null; value_number: number | null; display_name: string | null }> = {}
    for (const sp of stdParams ?? []) {
      paramValues[sp.parameters_id] = {
        value:        sp.text_value ?? null,
        value_number: sp.amount     ?? null,
        display_name: sp.parameter  ?? null,
      }
    }

    // Apply user-supplied overrides
    for (const [key, val] of Object.entries(parameters)) {
      const paramId = PARAM_ID_MAP[key] ?? key
      if (paramValues[paramId] !== undefined) {
        if (typeof val === 'number') {
          paramValues[paramId].value_number = val
        } else {
          paramValues[paramId].value = String(val)
        }
      }
    }

    // Insert all as company_parameters rows for this facility
    const companyParamRows = Object.entries(paramValues).map(([parameter_id, vals]) => ({
      company_id:   companyId,
      facility_id:  facilityId,
      parameter_id,
      value:        vals.value,
      value_number: vals.value_number,
      display_name: vals.display_name,
      created_by:   teamMemberId,
    }))

    if (companyParamRows.length > 0) {
      const { error: cpErr } = await supabase
        .from('company_parameters')
        .insert(companyParamRows)
      if (cpErr) throw cpErr
    }

    // 5b. Seed default restock categories
    const { error: rcErr } = await supabase
      .from('restock_category')
      .insert([
        // is_global: true on all three — they're system-seeded and
        // non-deletable. is_default still marks the single auto-pick
        // category (Standard) for new items where the user hasn't
        // chosen one explicitly. See migration 20260505000001.
        { facility_id: facilityId, company_id: companyId, name: 'Quick Restock', description: 'Items available locally within 1-2 weeks', target_months: 3, reorder_months: 0.5, is_default: false, is_global: true, sort_order: 1 },
        { facility_id: facilityId, company_id: companyId, name: 'Standard', description: 'Typical supplies with standard lead times', target_months: 6, reorder_months: 1.5, is_default: true, is_global: true, sort_order: 2 },
        { facility_id: facilityId, company_id: companyId, name: 'Extended Lead', description: 'Imports, custom prints, or specialty items', target_months: 12, reorder_months: 6, is_default: false, is_global: true, sort_order: 3 },
      ])
    if (rcErr) throw rcErr

    // 5c–5d: consumable_type + product_type are global (company_id IS NULL)
    //         — no per-company seeding needed

    // 6. Create Stripe customer
    const stripeCustomer = await stripe.customers.create({
      email,
      name: company_name,
      metadata: { company_id: companyId, admin_name },
    })
    stripeCustomerId = stripeCustomer.id

    // 7. Store stripe_customer_id on company record
    const { error: stripeIdErr } = await supabase
      .from('companies')
      .update({ stripe_customer_id: stripeCustomerId })
      .eq('company_id', companyId)
    if (stripeIdErr) throw stripeIdErr

    // 8. Create trial subscription row in DB
    const trialEnd = new Date(Date.now() + TRIAL_DAYS * 24 * 60 * 60 * 1000)
    subscriptionId = crypto.randomUUID()
    const { error: subErr } = await supabase
      .from('subscriptions')
      .insert({
        subscription_id:    subscriptionId,
        company_id:         companyId,
        stripe_customer_id: stripeCustomerId,
        plan_id:            plan_id || 'starter',
        billing_interval:   billing_interval === 'annual' ? 'annual' : 'monthly',
        status:             'trialing',
        trial_end:          trialEnd.toISOString(),
        created_by:         teamMemberId,
      })
    if (subErr) throw subErr

    // ── Send welcome email via Resend (non-blocking) ───────────────────────
    try {
      const resendKey = Deno.env.get('RESEND_API_KEY')
      if (resendKey) {
        const firstName = admin_name.split(' ')[0]
        await fetch('https://api.resend.com/emails', {
          method: 'POST',
          headers: {
            'Authorization': `Bearer ${resendKey}`,
            'Content-Type': 'application/json',
          },
          body: JSON.stringify({
            from: 'STRATA <roast@strataroast.com>',
            to: [email],
            subject: `Welcome to STRATA, ${firstName}!`,
            html: welcomeEmailHtml(admin_name, company_name, TRIAL_DAYS),
          }),
        })
      }
    } catch (_emailErr) {
      // Swallow — welcome email is nice-to-have, not critical
    }

    // ── Return success ───────────────────────────────────────────────────────
    return json({
      success:        true,
      company_id:     companyId,
      facility_id:    facilityId,
      team_member_id: teamMemberId,
      trial_end:      trialEnd.toISOString(),
    })

  } catch (err) {
    // Full rollback — delete in reverse insertion order
    if (subscriptionId) {
      await supabase.from('subscriptions').delete().eq('subscription_id', subscriptionId)
    }
    if (stripeCustomerId) {
      await stripe.customers.del(stripeCustomerId).catch(() => {})
    }
    if (teamMemberId) {
      await supabase.from('team').delete().eq('team_member_id', teamMemberId)
    }
    if (companyId) {
      // CASCADE: also removes facilities rows and company_parameters rows
      await supabase.from('companies').delete().eq('company_id', companyId)
    }
    // Delete auth user last so the email is freed up for a retry
    await supabase.auth.admin.deleteUser(authUserId)
    const message = err instanceof Error ? err.message : 'Database error during onboarding'
    return json({ error: message }, 500)
  }
})

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
