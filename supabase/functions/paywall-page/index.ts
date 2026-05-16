import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FALLBACK_LOGO = 'https://pwpslalerytymorcodlv.supabase.co/storage/v1/object/public/Branding/STRATOS%20Full%20Logo%20-%2075ppi.png'

Deno.serve(async (req) => {
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204 })
  }

  let logoUrl = FALLBACK_LOGO
  try {
    const supabase = createClient(
      Deno.env.get('SUPABASE_URL')!,
      Deno.env.get('SUPABASE_SERVICE_ROLE_KEY')!,
      { auth: { autoRefreshToken: false, persistSession: false } }
    )
    const { data } = await supabase
      .from('get_started')
      .select('image_url')
      .limit(1)
      .single()
    if (data?.image_url) logoUrl = data.image_url
  } catch {
    // fall through to fallback
  }

  const html = buildHtml(logoUrl)

  return new Response(html, {
    status: 200,
    headers: {
      'Content-Type': 'text/html; charset=utf-8',
      'Cache-Control': 'no-cache, no-store, must-revalidate',
    },
  })
})

function buildHtml(logoUrl: string): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0" />
  <title>RoastOS — Subscribe to Continue</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --brown:     #3e260e;
      --brown-mid: #5c3a18;
      --tan:       #d4a96a;
      --cream:     #fdf6ec;
      --surface:   #ffffff;
      --border:    #e0d0c0;
      --text:      #2d1e1a;
      --muted:     #7a6040;
      --error:     #c0392b;
      --radius:    8px;
      --shadow:    0 2px 12px rgba(74,44,42,0.10);
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: var(--cream);
      color: var(--text);
      min-height: 100vh;
      display: flex;
      align-items: flex-start;
      justify-content: center;
      padding: 40px 16px 60px;
    }
    .wrap { width: 100%; max-width: 900px; }

    .header {
      background: #ffffff;
      border-radius: 14px 14px 0 0;
      padding: 24px 32px 20px;
      border-bottom: 3px solid #e0d0c0;
      text-align: center;
    }
    .header img { height: 48px; display: block; margin: 0 auto 8px; }
    .header p  { font-size: 0.92rem; color: #7a6040; }

    .body { background: var(--surface); border-radius: 0 0 14px 14px; padding: 32px; box-shadow: var(--shadow); }

    .alert {
      background: #fff8ec;
      border: 1.5px solid var(--tan);
      border-radius: var(--radius);
      padding: 14px 18px;
      text-align: center;
      font-size: 0.90rem;
      color: var(--brown);
      font-weight: 600;
      margin-bottom: 28px;
    }

    .plan-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
      gap: 14px;
    }

    .plan-card {
      border: 2px solid var(--border);
      border-radius: 10px;
      padding: 20px 18px 18px;
      display: flex;
      flex-direction: column;
      position: relative;
    }
    .plan-card.popular::before {
      content: 'Most popular';
      position: absolute;
      top: -11px; left: 50%;
      transform: translateX(-50%);
      background: var(--tan);
      color: var(--brown);
      font-size: 0.68rem;
      font-weight: 700;
      letter-spacing: 0.06em;
      text-transform: uppercase;
      padding: 3px 10px;
      border-radius: 20px;
      white-space: nowrap;
    }

    .plan-name  { font-size: 1rem; font-weight: 700; color: var(--brown); margin-bottom: 4px; }
    .plan-price { font-size: 0.82rem; color: var(--muted); margin-bottom: 14px; }

    .plan-features { list-style: none; flex: 1; }
    .plan-features li {
      font-size: 0.80rem;
      color: var(--text);
      padding: 4px 0;
      display: flex;
      align-items: flex-start;
      gap: 7px;
      line-height: 1.35;
    }
    .plan-features li::before { content: '✓'; color: var(--tan); font-weight: 700; flex-shrink: 0; margin-top: 1px; }
    .plan-features li.inherited { color: var(--muted); }

    .subscribe-btn {
      margin-top: 16px;
      width: 100%;
      padding: 10px;
      background: var(--brown);
      color: white;
      border: none;
      border-radius: var(--radius);
      font-size: 0.88rem;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.15s, opacity 0.15s;
    }
    .subscribe-btn:hover { background: var(--brown-mid); }
    .subscribe-btn:disabled { opacity: 0.55; cursor: not-allowed; }

    .error-banner {
      background: #fdf0ef;
      border: 1.5px solid #f5c6c2;
      border-radius: var(--radius);
      color: var(--error);
      font-size: 0.85rem;
      padding: 11px 14px;
      margin-top: 20px;
      display: none;
      text-align: center;
    }
    .error-banner.visible { display: block; }

    .footer-note {
      text-align: center;
      font-size: 0.78rem;
      color: var(--muted);
      margin-top: 22px;
    }
  </style>
</head>
<body>
<div class="wrap">
  <div class="header">
    <img src="${logoUrl}" alt="RoastOS" />
    <p>Your trial has ended — subscribe to keep access</p>
  </div>
  <div class="body">
    <div class="alert">Your 14-day trial has expired. Choose a plan below to continue using RoastOS.</div>

    <div class="plan-grid">

      <div class="plan-card">
        <div class="plan-name">Starter</div>
        <div class="plan-price">$50 / month</div>
        <ul class="plan-features">
          <li>Roast recipes &amp; logs</li>
          <li>Weekly roast planning</li>
          <li>Order tracking</li>
          <li>Packing &amp; delivery management</li>
          <li>Up to 1 facility</li>
        </ul>
        <button class="subscribe-btn" onclick="subscribe('starter', this)">Subscribe — Starter</button>
      </div>

      <div class="plan-card popular">
        <div class="plan-name">Pro</div>
        <div class="plan-price">$100 / month</div>
        <ul class="plan-features">
          <li class="inherited">Everything in Starter</li>
          <li>Automated inventory tracking</li>
          <li>COGS tracking</li>
          <li>Company-wide reports</li>
          <li>Up to 1 facility</li>
        </ul>
        <button class="subscribe-btn" onclick="subscribe('pro', this)">Subscribe — Pro</button>
      </div>

      <div class="plan-card">
        <div class="plan-name">Enterprise</div>
        <div class="plan-price">$200 / month</div>
        <ul class="plan-features">
          <li class="inherited">Everything in Pro</li>
          <li>CRM module</li>
          <li>Maintenance module</li>
          <li>Up to 1 facility</li>
        </ul>
        <button class="subscribe-btn" onclick="subscribe('enterprise', this)">Subscribe — Enterprise</button>
      </div>

      <div class="plan-card">
        <div class="plan-name">Enterprise+</div>
        <div class="plan-price">Contact us</div>
        <ul class="plan-features">
          <li class="inherited">Everything in Enterprise</li>
          <li>Multiple facilities</li>
          <li>Custom setup &amp; onboarding</li>
          <li>Priority support</li>
        </ul>
        <button class="subscribe-btn" onclick="contactUs()">Contact Us</button>
      </div>

    </div>

    <div class="error-banner" id="errorBanner"></div>

    <p class="footer-note">Secure payment processing by Stripe. Cancel any time.</p>
  </div>
</div>

<script>
  var SUPABASE_URL        = 'https://pwpslalerytymorcodlv.supabase.co'
  var SUPABASE_ANON_KEY   = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3cHNsYWxlcnl0eW1vcmNvZGx2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0MjM3NDcsImV4cCI6MjA4Mzk5OTc0N30.MZsWvHwfhNirxwC4tC6tkiT3_fBn3ZMK0AvjZ0YaaTQ'
  var CHECKOUT_FN         = SUPABASE_URL + '/functions/v1/create-checkout'

  var params    = new URLSearchParams(window.location.search)
  var companyId = params.get('company_id') || ''

  async function subscribe(planId, btn) {
    if (!companyId) {
      showError('Missing company ID. Please return to the app and try again.')
      return
    }
    btn.disabled = true
    btn.textContent = 'Redirecting to checkout\u2026'
    hideError()

    try {
      var res = await fetch(CHECKOUT_FN, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
          apikey: SUPABASE_ANON_KEY,
          Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
        },
        body: JSON.stringify({
          company_id:  companyId,
          plan_id:     planId,
          success_url: window.location.origin + '/functions/v1/signup-page?subscribed=1&company_id=' + companyId,
          cancel_url:  window.location.href,
        }),
      })
      var data = await res.json()
      if (!res.ok || !data.url) throw new Error(data.error || 'Could not start checkout')
      window.location.href = data.url
    } catch (err) {
      btn.disabled = false
      btn.textContent = 'Try again'
      showError(err.message || 'Something went wrong. Please try again.')
    }
  }

  function contactUs() {
    window.location.href = 'mailto:hello@roastceo.com?subject=Enterprise%2B%20Inquiry'
  }

  function showError(msg) {
    var el = document.getElementById('errorBanner')
    el.textContent = msg
    el.classList.add('visible')
  }
  function hideError() {
    document.getElementById('errorBanner').classList.remove('visible')
  }
</script>
</body>
</html>`
}
