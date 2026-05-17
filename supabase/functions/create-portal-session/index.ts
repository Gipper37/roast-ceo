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

  const { company_id, return_url } = body as { company_id: string; return_url: string }

  if (!company_id || !return_url) {
    return json({ error: 'Missing required fields: company_id, return_url' }, 400)
  }

  // Verify the caller actually belongs to this company. Without this
  // anyone discovering the function URL could POST with any company_id
  // and open the Stripe billing portal (cancel/modify subscription).
  const access = await verifyCompanyAccess(req, company_id)
  if (!access.ok) return access.response

  // Look up stripe_customer_id for this company
  const { data: company, error: companyErr } = await supabase
    .from('companies')
    .select('stripe_customer_id, company_name')
    .eq('company_id', company_id)
    .single()

  if (companyErr || !company) {
    return json({ error: 'Company not found' }, 404)
  }

  if (!company.stripe_customer_id) {
    return json({ error: 'No billing account found. Please subscribe first.' }, 400)
  }

  // Create a Stripe Billing Portal session
  const session = await stripe.billingPortal.sessions.create({
    customer: company.stripe_customer_id,
    return_url,
  })

  return json({ url: session.url })
})

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...corsHeaders, 'Content-Type': 'application/json' },
  })
}
