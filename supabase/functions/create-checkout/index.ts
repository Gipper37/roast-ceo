import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14?target=deno'
import { corsHeaders } from '../_shared/cors.ts'
import { verifyCompanyAccess } from '../_shared/verifyCompanyAccess.ts'

Deno.serve(async (req) => {
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

  const { company_id, plan_id, billing_interval = 'monthly', success_url, cancel_url } = body as {
    company_id:       string
    plan_id:          string
    billing_interval?: string
    success_url:      string
    cancel_url:       string
  }

  if (!company_id || !plan_id || !success_url || !cancel_url) {
    return json({ error: 'Missing required fields: company_id, plan_id, success_url, cancel_url' }, 400)
  }

  // Verify the caller actually belongs to this company. Without this
  // anyone discovering the function URL could POST with any company_id
  // and trigger a Stripe checkout session for that company.
  const access = await verifyCompanyAccess(req, company_id)
  if (!access.ok) return access.response

  // Look up company's Stripe customer ID
  const { data: company, error: companyErr } = await supabase
    .from('companies')
    .select('stripe_customer_id, company_name')
    .eq('company_id', company_id)
    .single()

  if (companyErr || !company) {
    return json({ error: 'Company not found' }, 404)
  }

  if (!company.stripe_customer_id) {
    return json({ error: 'No Stripe customer linked to this company' }, 400)
  }

  // Look up the Stripe price ID for the requested plan + interval
  const isAnnual = billing_interval === 'annual'
  const { data: plan, error: planErr } = await supabase
    .from('subscription_plans')
    .select('stripe_price_id, stripe_annual_price_id, plan_name')
    .eq('plan_id', plan_id)
    .eq('active', true)
    .single()

  if (planErr || !plan) {
    return json({ error: `Plan '${plan_id}' not found` }, 404)
  }

  const priceId = isAnnual ? (plan.stripe_annual_price_id || plan.stripe_price_id) : plan.stripe_price_id

  if (!priceId) {
    return json({ error: `No Stripe price configured for plan '${plan_id}'` }, 400)
  }

  // Create Stripe Checkout session
  const session = await stripe.checkout.sessions.create({
    customer:              company.stripe_customer_id,
    mode:                  'subscription',
    allow_promotion_codes: true,
    line_items:            [{ price: priceId, quantity: 1 }],
    success_url,
    cancel_url,
    metadata:              { company_id, plan_id },
    subscription_data: {
      metadata: { company_id, plan_id },
    },
  })

  return json({ url: session.url })
})

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
