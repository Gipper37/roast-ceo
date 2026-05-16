import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'
import Stripe from 'https://esm.sh/stripe@14?target=deno'
import { corsHeaders } from '../_shared/cors.ts'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response('ok', { headers: corsHeaders })
  }

  const stripe = new Stripe(Deno.env.get('STRIPE_SECRET_KEY')!, {
    apiVersion: '2024-06-20',
    httpClient: Stripe.createFetchHttpClient(),
  })

  const supabase = createClient(
    Deno.env.get('SUPABASE_URL')!,
    Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
    { auth: { autoRefreshToken: false, persistSession: false } }
  )

  // Verify Stripe signature
  const signature = req.headers.get('stripe-signature')
  if (!signature) {
    return new Response('Missing stripe-signature header', { status: 400 })
  }

  const webhookSecret = Deno.env.get('STRIPE_WEBHOOK_SECRET')!
  const body = await req.text()

  let event: Stripe.Event
  try {
    event = await stripe.webhooks.constructEventAsync(body, signature, webhookSecret)
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Webhook verification failed'
    console.error('Webhook signature verification failed:', message)
    return new Response(`Webhook Error: ${message}`, { status: 400 })
  }

  console.log(`Processing Stripe event: ${event.type}`)

  try {
    switch (event.type) {

      case 'customer.subscription.created':
      case 'customer.subscription.updated': {
        const sub = event.data.object as Stripe.Subscription
        const customerId = typeof sub.customer === 'string' ? sub.customer : sub.customer.id

        // Resolve plan_id from price — check both monthly and annual price columns
        const priceId = sub.items.data[0]?.price?.id ?? null
        const interval = sub.items.data[0]?.price?.recurring?.interval ?? 'month'
        const billingInterval = interval === 'year' ? 'annual' : 'monthly'

        // Try monthly price first, then annual
        let planId: string | null = null
        const { data: monthlyRow } = await supabase
          .from('subscription_plans')
          .select('plan_id')
          .eq('stripe_price_id', priceId)
          .maybeSingle()
        if (monthlyRow) {
          planId = monthlyRow.plan_id
        } else {
          const { data: annualRow } = await supabase
            .from('subscription_plans')
            .select('plan_id')
            .eq('stripe_annual_price_id', priceId)
            .maybeSingle()
          planId = annualRow?.plan_id ?? null
        }

        await supabase
          .from('subscriptions')
          .upsert({
            stripe_subscription_id: sub.id,
            stripe_customer_id:     customerId,
            plan_id:                planId,
            billing_interval:       billingInterval,
            status:                 sub.status,
            trial_end:              sub.trial_end ? new Date(sub.trial_end * 1000).toISOString() : null,
            current_period_start:   new Date(sub.current_period_start * 1000).toISOString(),
            current_period_end:     new Date(sub.current_period_end * 1000).toISOString(),
            cancel_at_period_end:   sub.cancel_at_period_end,
            canceled_at:            sub.canceled_at ? new Date(sub.canceled_at * 1000).toISOString() : null,
            updated_at:             new Date().toISOString(),
          }, { onConflict: 'stripe_subscription_id' })
        break
      }

      case 'customer.subscription.deleted': {
        const sub = event.data.object as Stripe.Subscription
        await supabase
          .from('subscriptions')
          .update({
            status:      'canceled',
            canceled_at: new Date().toISOString(),
            updated_at:  new Date().toISOString(),
          })
          .eq('stripe_subscription_id', sub.id)
        break
      }

      case 'invoice.payment_failed': {
        const invoice = event.data.object as Stripe.Invoice
        const subId = typeof invoice.subscription === 'string'
          ? invoice.subscription
          : invoice.subscription?.id
        if (subId) {
          await supabase
            .from('subscriptions')
            .update({ status: 'past_due', updated_at: new Date().toISOString() })
            .eq('stripe_subscription_id', subId)
        }
        break
      }

      case 'invoice.payment_succeeded': {
        const invoice = event.data.object as Stripe.Invoice
        const subId = typeof invoice.subscription === 'string'
          ? invoice.subscription
          : invoice.subscription?.id
        if (subId) {
          await supabase
            .from('subscriptions')
            .update({ status: 'active', updated_at: new Date().toISOString() })
            .eq('stripe_subscription_id', subId)
        }
        break
      }

      case 'customer.subscription.trial_will_end': {
        // Trial ending in 3 days — log for now, wire up email notification later
        const sub = event.data.object as Stripe.Subscription
        console.log(`Trial ending soon for subscription: ${sub.id}`)
        break
      }

      default:
        console.log(`Unhandled event type: ${event.type}`)
    }

    return new Response(JSON.stringify({ received: true }), {
      headers: { 'Content-Type': 'application/json' },
    })

  } catch (err) {
    const message = err instanceof Error ? err.message : 'Handler error'
    console.error(`Error handling ${event.type}:`, message)
    return new Response(`Handler error: ${message}`, { status: 500 })
  }
})
