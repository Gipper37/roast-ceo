import { createClient } from 'https://esm.sh/@supabase/supabase-js@2'

const FALLBACK_LOGO = 'https://pwpslalerytymorcodlv.supabase.co/storage/v1/object/public/Branding/STRATOS%20Full%20Logo%20-%2075ppi.png'

Deno.serve(async (req) => {
  // Allow GET and OPTIONS only
  if (req.method === 'OPTIONS') {
    return new Response(null, { status: 204 })
  }

  // Fetch logo URL from get_started table
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
  <title>RoastOS — New Company Sign Up</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }

    :root {
      --brown:      #3e260e;
      --brown-mid:  #5c3a18;
      --tan:        #d4a96a;
      --cream:      #fdf6ec;
      --surface:    #ffffff;
      --border:     #e0d0c0;
      --text:       #2d1e0a;
      --muted:      #7a6040;
      --error:      #c0392b;
      --success-bg: #eaf4ea;
      --success:    #27643a;
      --radius:     8px;
      --shadow:     0 2px 12px rgba(74,44,42,0.10);
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

    /* ── Plan picker (Step 1) ─────────────────────────────────────────── */
    .plan-wrap {
      width: 100%;
      max-width: 900px;
    }
    .plan-header {
      background: #ffffff;
      border-radius: 14px 14px 0 0;
      padding: 24px 32px 20px;
      border-bottom: 3px solid var(--border);
    }
    .plan-header img { height: 48px; display: block; }
    .plan-header p  { font-size: 0.88rem; color: var(--muted); margin-top: 6px; }

    .plan-body { background: var(--surface); border-radius: 0 0 14px 14px; padding: 32px; box-shadow: var(--shadow); }

    .plan-trial-note {
      text-align: center;
      font-size: 0.85rem;
      color: var(--muted);
      margin-bottom: 24px;
    }
    .plan-trial-note strong { color: var(--brown); }

    .plan-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(190px, 1fr));
      gap: 14px;
    }

    .plan-card {
      border: 2px solid var(--border);
      border-radius: 10px;
      padding: 20px 18px 18px;
      cursor: pointer;
      transition: border-color 0.15s, box-shadow 0.15s, background 0.15s;
      position: relative;
      display: flex;
      flex-direction: column;
    }
    .plan-card:hover { border-color: var(--tan); box-shadow: 0 2px 8px rgba(74,44,42,0.10); }
    .plan-card.selected {
      border-color: var(--brown);
      background: #fdf1e1;
      box-shadow: 0 2px 10px rgba(74,44,42,0.15);
    }
    .plan-card.popular::before {
      content: 'Most popular';
      position: absolute;
      top: -11px;
      left: 50%;
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

    .plan-name {
      font-size: 1rem;
      font-weight: 700;
      color: var(--brown);
      margin-bottom: 4px;
    }
    .plan-price {
      font-size: 0.82rem;
      color: var(--muted);
      margin-bottom: 14px;
    }
    .plan-features {
      list-style: none;
      flex: 1;
    }
    .plan-features li {
      font-size: 0.80rem;
      color: var(--text);
      padding: 4px 0;
      display: flex;
      align-items: flex-start;
      gap: 7px;
      line-height: 1.35;
    }
    .plan-features li::before {
      content: '✓';
      color: var(--tan);
      font-weight: 700;
      flex-shrink: 0;
      margin-top: 1px;
    }
    .plan-features li.inherited { color: var(--muted); }

    .plan-select-btn {
      margin-top: 16px;
      width: 100%;
      padding: 9px;
      border: 1.5px solid var(--brown);
      border-radius: var(--radius);
      background: transparent;
      color: var(--brown);
      font-size: 0.85rem;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.15s, color 0.15s;
    }
    .plan-card.selected .plan-select-btn {
      background: var(--brown);
      color: white;
    }
    .plan-select-btn:hover { background: var(--brown); color: white; }

    .plan-continue-btn {
      width: 100%;
      margin-top: 28px;
      padding: 13px;
      background: var(--brown);
      color: white;
      border: none;
      border-radius: var(--radius);
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.15s;
    }
    .plan-continue-btn:hover { background: var(--brown-mid); }

    /* ── Signup form (Step 2) ─────────────────────────────────────────── */
    .card {
      background: var(--surface);
      border-radius: 14px;
      box-shadow: var(--shadow);
      width: 100%;
      max-width: 560px;
      overflow: hidden;
    }

    .card-header {
      background: #ffffff;
      padding: 24px 32px 20px;
      border-bottom: 3px solid var(--border);
    }
    .card-header img { height: 44px; display: block; }
    .card-header p  { font-size: 0.88rem; color: var(--muted); margin-top: 6px; }
    .card-header .plan-badge {
      display: inline-block;
      margin-top: 10px;
      background: var(--tan);
      color: var(--brown);
      border-radius: 20px;
      padding: 3px 11px;
      font-size: 0.78rem;
      font-weight: 600;
    }

    .back-link {
      display: inline-flex;
      align-items: center;
      gap: 5px;
      font-size: 0.80rem;
      color: var(--muted);
      cursor: pointer;
      margin-bottom: 18px;
      background: none;
      border: none;
      padding: 0;
    }
    .back-link:hover { color: var(--brown); }

    .card-body { padding: 28px 32px 32px; }

    .section-label {
      font-size: 0.72rem;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--muted);
      margin-bottom: 16px;
    }

    .field { margin-bottom: 18px; }

    label {
      display: block;
      font-size: 0.83rem;
      font-weight: 600;
      color: var(--brown);
      margin-bottom: 5px;
    }

    input[type="text"],
    input[type="email"],
    input[type="password"],
    input[type="number"],
    select {
      width: 100%;
      padding: 9px 12px;
      border: 1.5px solid var(--border);
      border-radius: var(--radius);
      font-size: 0.93rem;
      color: var(--text);
      background: var(--surface);
      transition: border-color 0.15s;
      appearance: none;
      -webkit-appearance: none;
    }
    select {
      background-image: url("data:image/svg+xml,%3Csvg xmlns='http://www.w3.org/2000/svg' width='12' height='8' viewBox='0 0 12 8'%3E%3Cpath d='M1 1l5 5 5-5' stroke='%234a2c2a' stroke-width='1.5' fill='none' stroke-linecap='round' stroke-linejoin='round'/%3E%3C/svg%3E");
      background-repeat: no-repeat;
      background-position: right 12px center;
      padding-right: 36px;
      cursor: pointer;
    }
    input:focus, select:focus {
      outline: none;
      border-color: var(--tan);
      box-shadow: 0 0 0 3px rgba(212,169,106,0.18);
    }
    input.invalid, select.invalid { border-color: var(--error); }

    .field-hint  { font-size: 0.76rem; color: var(--muted); margin-top: 4px; }
    .field-error { font-size: 0.76rem; color: var(--error); margin-top: 4px; display: none; }

    .row-2 { display: grid; grid-template-columns: 1fr 1fr; gap: 14px; }

    .units-group { display: flex; gap: 10px; }
    .units-group label {
      flex: 1;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 7px;
      padding: 8px 12px;
      border: 1.5px solid var(--border);
      border-radius: var(--radius);
      cursor: pointer;
      font-size: 0.88rem;
      transition: border-color 0.15s, background 0.15s;
      margin-bottom: 0;
    }
    .units-group input[type="radio"] { width: auto; }
    .units-group label:has(input:checked) {
      border-color: var(--tan);
      background: #fdf1e1;
      color: var(--brown);
    }

    .config-toggle {
      width: 100%;
      background: none;
      border: 1.5px solid var(--border);
      border-radius: var(--radius);
      padding: 10px 14px;
      font-size: 0.85rem;
      font-weight: 600;
      color: var(--muted);
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: space-between;
      margin: 22px 0 0;
      transition: border-color 0.15s, color 0.15s;
    }
    .config-toggle:hover { border-color: var(--tan); color: var(--brown); }
    .config-toggle .arrow { transition: transform 0.2s; }
    .config-toggle.open .arrow { transform: rotate(180deg); }

    .config-body { display: none; padding-top: 20px; border-top: 1px solid var(--border); margin-top: 16px; }
    .config-body.open { display: block; }

    .submit-btn {
      width: 100%;
      padding: 13px;
      background: var(--brown);
      color: white;
      border: none;
      border-radius: var(--radius);
      font-size: 1rem;
      font-weight: 700;
      cursor: pointer;
      margin-top: 24px;
      transition: background 0.15s, opacity 0.15s;
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 10px;
    }
    .submit-btn:hover:not(:disabled) { background: var(--brown-mid); }
    .submit-btn:disabled { opacity: 0.55; cursor: not-allowed; }

    .spinner {
      width: 18px; height: 18px;
      border: 2.5px solid rgba(255,255,255,0.35);
      border-top-color: white;
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
      display: none;
    }
    .submit-btn.loading .spinner { display: block; }
    .submit-btn.loading .btn-text { opacity: 0.7; }
    @keyframes spin { to { transform: rotate(360deg); } }

    .error-banner {
      background: #fdf0ef;
      border: 1.5px solid #f5c6c2;
      border-radius: var(--radius);
      color: var(--error);
      font-size: 0.85rem;
      padding: 11px 14px;
      margin-top: 16px;
      display: none;
    }
    .error-banner.visible { display: block; }

    .success-card {
      display: none;
      text-align: center;
      padding: 40px 32px;
    }
    .success-card.visible { display: block; }
    .success-card .check { font-size: 2.8rem; margin-bottom: 14px; }
    .success-card h2 { font-size: 1.25rem; color: var(--success); margin-bottom: 8px; }
    .success-card p  { font-size: 0.87rem; color: var(--muted); margin-bottom: 20px; }
    .success-trial {
      background: var(--success-bg);
      border-radius: var(--radius);
      padding: 12px 16px;
      font-size: 0.85rem;
      color: var(--success);
      font-weight: 600;
    }
  </style>
</head>
<body>

  <!-- ── Step 1: Plan picker ─────────────────────────────────────────── -->
  <div class="plan-wrap" id="planStep">
    <div class="plan-header">
      <img src="${logoUrl}" alt="RoastOS" />
      <p>Choose your plan — all plans start with a 14-day free trial</p>
    </div>
    <div class="plan-body">
      <p class="plan-trial-note"><strong>No credit card required.</strong> Try any plan free for 14 days.</p>

      <div class="plan-grid">

        <!-- Starter -->
        <div class="plan-card selected" data-plan="starter" onclick="selectPlan(this)">
          <div class="plan-name">Starter</div>
          <div class="plan-price">$50 / month</div>
          <ul class="plan-features">
            <li>Roast recipes &amp; logs</li>
            <li>Weekly roast planning</li>
            <li>Order tracking</li>
            <li>Packing &amp; delivery management</li>
            <li>Up to 1 facility</li>
          </ul>
          <button class="plan-select-btn" type="button">Selected ✓</button>
        </div>

        <!-- Pro -->
        <div class="plan-card popular" data-plan="pro" onclick="selectPlan(this)">
          <div class="plan-name">Pro</div>
          <div class="plan-price">$100 / month</div>
          <ul class="plan-features">
            <li class="inherited">Everything in Starter</li>
            <li>Automated inventory tracking</li>
            <li>COGS tracking</li>
            <li>Company-wide reports</li>
            <li>Up to 1 facility</li>
          </ul>
          <button class="plan-select-btn" type="button">Select Pro</button>
        </div>

        <!-- Enterprise -->
        <div class="plan-card" data-plan="enterprise" onclick="selectPlan(this)">
          <div class="plan-name">Enterprise</div>
          <div class="plan-price">$200 / month</div>
          <ul class="plan-features">
            <li class="inherited">Everything in Pro</li>
            <li>CRM module</li>
            <li>Maintenance module</li>
            <li>Up to 1 facility</li>
          </ul>
          <button class="plan-select-btn" type="button">Select Enterprise</button>
        </div>

        <!-- Enterprise+ -->
        <div class="plan-card" data-plan="enterprise_plus" onclick="selectPlan(this)">
          <div class="plan-name">Enterprise+</div>
          <div class="plan-price">Contact us</div>
          <ul class="plan-features">
            <li class="inherited">Everything in Enterprise</li>
            <li>Multiple facilities</li>
            <li>Custom setup &amp; onboarding</li>
            <li>Priority support</li>
          </ul>
          <button class="plan-select-btn" type="button">Select Enterprise+</button>
        </div>

      </div>

      <button class="plan-continue-btn" onclick="goToSignup()">
        Start free trial →
      </button>
    </div>
  </div>

  <!-- ── Step 2: Signup form ─────────────────────────────────────────── -->
  <div class="card" id="signupStep" style="display:none">

    <!-- Success state -->
    <div class="success-card" id="successCard">
      <div class="check">&#9749;</div>
      <h2>Account created!</h2>
      <p>Your roastery is ready. Check your email, then sign into the app.</p>
      <div class="success-trial">Your 14-day free trial has started. No credit card needed.</div>
    </div>

    <!-- Form -->
    <div id="formWrap">
      <div class="card-header">
        <img src="${logoUrl}" alt="RoastOS" />
        <p>Set up your roastery — takes about 2 minutes</p>
        <span class="plan-badge" id="selectedPlanBadge">Starter plan</span>
      </div>

      <div class="card-body">
        <button class="back-link" type="button" onclick="goBack()">← Back to plans</button>

        <form id="signupForm" novalidate>
          <div class="section-label">Company &amp; Admin</div>

          <div class="row-2">
            <div class="field">
              <label for="companyName">Company name</label>
              <input type="text" id="companyName" name="company_name" required autocomplete="organization" />
              <div class="field-error" id="err-companyName">Required</div>
            </div>
            <div class="field">
              <label for="facilityName">Facility name</label>
              <input type="text" id="facilityName" name="facility_name" required placeholder="Main Roastery" />
              <div class="field-error" id="err-facilityName">Required</div>
            </div>
          </div>

          <div class="row-2">
            <div class="field">
              <label for="country">Country</label>
              <select id="country" name="country_code" required>
                <option value="">Loading…</option>
              </select>
              <div class="field-error" id="err-country">Required</div>
            </div>
            <div class="field">
              <label for="timezone">Timezone</label>
              <select id="timezone" name="timezone" required>
                <option value="">Loading…</option>
              </select>
              <div class="field-error" id="err-timezone">Required</div>
            </div>
          </div>

          <div class="field">
            <label for="adminName">Your name</label>
            <input type="text" id="adminName" name="admin_name" required autocomplete="name" />
            <div class="field-error" id="err-adminName">Required</div>
          </div>

          <div class="field">
            <label for="email">Email</label>
            <input type="email" id="email" name="email" required autocomplete="email" />
            <div class="field-error" id="err-email">Enter a valid email</div>
          </div>

          <div class="row-2">
            <div class="field">
              <label for="password">Password</label>
              <input type="password" id="password" name="password" required minlength="8" autocomplete="new-password" />
              <div class="field-error" id="err-password">Min 8 characters</div>
            </div>
            <div class="field">
              <label for="confirmPassword">Confirm password</label>
              <input type="password" id="confirmPassword" required autocomplete="new-password" />
              <div class="field-error" id="err-confirmPassword">Passwords don't match</div>
            </div>
          </div>

          <!-- Config (collapsible) -->
          <button type="button" class="config-toggle" id="configToggle">
            <span>Customize roastery defaults</span>
            <span class="arrow">&#9660;</span>
          </button>

          <div class="config-body" id="configBody">
            <div class="section-label" style="margin-top:4px">Configuration</div>

            <div class="field">
              <label>Weight units</label>
              <div class="units-group">
                <label><input type="radio" name="units" value="lbs" checked /> LBS</label>
                <label><input type="radio" name="units" value="kg" /> KG</label>
              </div>
            </div>

            <div class="row-2">
              <div class="field">
                <label for="retentionRate">Retention rate (%)</label>
                <input type="number" id="retentionRate" name="retention_rate" min="50" max="99" step="1" value="82" />
                <div class="field-hint">Green weight lost to roasting. Default 82%.</div>
              </div>
              <div class="field">
                <label for="chargeWeight" id="chargeWeightLabel">Charge weight (lbs)</label>
                <input type="number" id="chargeWeight" name="charge_weight" min="1" max="1000" step="0.5" value="25" />
                <div class="field-hint">Typical batch size.</div>
              </div>
            </div>

            <div class="row-2">
              <div class="field">
                <label for="roastResetDay">Roast week resets on</label>
                <select id="roastResetDay" name="roast_reset_day">
                  <option value="0">Sunday</option>
                  <option value="1">Monday</option>
                  <option value="2">Tuesday</option>
                  <option value="3">Wednesday</option>
                  <option value="4" selected>Thursday</option>
                  <option value="5">Friday</option>
                  <option value="6">Saturday</option>
                </select>
              </div>
              <div class="field">
                <label for="ordersResetDay">Orders week resets on</label>
                <select id="ordersResetDay" name="orders_reset_day">
                  <option value="0">Sunday</option>
                  <option value="1" selected>Monday</option>
                  <option value="2">Tuesday</option>
                  <option value="3">Wednesday</option>
                  <option value="4">Thursday</option>
                  <option value="5">Friday</option>
                  <option value="6">Saturday</option>
                </select>
              </div>
            </div>
          </div>

          <div class="error-banner" id="errorBanner"></div>

          <button type="submit" class="submit-btn" id="submitBtn">
            <div class="spinner"></div>
            <span class="btn-text">Create account &amp; start trial</span>
          </button>
        </form>
      </div>
    </div>
  </div>

<script>
  const SUPABASE_URL      = 'https://pwpslalerytymorcodlv.supabase.co'
  const EDGE_FN_URL       = SUPABASE_URL + '/functions/v1/company-signup'
  const SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3cHNsYWxlcnl0eW1vcmNvZGx2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0MjM3NDcsImV4cCI6MjA4Mzk5OTc0N30.MZsWvHwfhNirxwC4tC6tkiT3_fBn3ZMK0AvjZ0YaaTQ'
  const API_HEADERS = { apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + SUPABASE_ANON_KEY }

  const PLAN_NAMES = {
    starter:         'Starter',
    pro:             'Pro',
    enterprise:      'Enterprise',
    enterprise_plus: 'Enterprise+',
  }

  let selectedPlanId = 'starter'

  // ── Plan picker ──────────────────────────────────────────────────────
  function selectPlan(card) {
    document.querySelectorAll('.plan-card').forEach(function(c) {
      c.classList.remove('selected')
      c.querySelector('.plan-select-btn').textContent = 'Select ' + PLAN_NAMES[c.dataset.plan]
    })
    card.classList.add('selected')
    card.querySelector('.plan-select-btn').textContent = 'Selected ✓'
    selectedPlanId = card.dataset.plan
  }

  function goToSignup() {
    document.getElementById('planStep').style.display = 'none'
    var signupStep = document.getElementById('signupStep')
    signupStep.style.display = 'block'
    document.getElementById('selectedPlanBadge').textContent = PLAN_NAMES[selectedPlanId] + ' plan'
    initLookups()
  }

  function goBack() {
    document.getElementById('signupStep').style.display = 'none'
    document.getElementById('planStep').style.display = 'block'
  }

  // ── Load timezones + countries ───────────────────────────────────────
  var lookupsLoaded = false
  async function initLookups() {
    if (lookupsLoaded) return
    lookupsLoaded = true
    var selTz      = document.getElementById('timezone')
    var selCountry = document.getElementById('country')

    var results = await Promise.all([
      fetch(SUPABASE_URL + '/rest/v1/setup_timezones?select=timezone_name,display_label&order=display_label', { headers: API_HEADERS }).then(function(r) { return r.json() }),
      fetch(SUPABASE_URL + '/rest/v1/setup_countries?select=country_code,country_name&order=country_name', { headers: API_HEADERS }).then(function(r) { return r.json() }),
    ])
    var tzData      = results[0]
    var countryData = results[1]

    var localTz = Intl.DateTimeFormat().resolvedOptions().timeZone
    selTz.innerHTML = '<option value="">Select a timezone\u2026</option>'
    tzData.forEach(function(tz) {
      var opt = document.createElement('option')
      opt.value = tz.timezone_name
      opt.textContent = tz.display_label
      if (tz.timezone_name === localTz) opt.selected = true
      selTz.appendChild(opt)
    })

    selCountry.innerHTML = '<option value="">Select a country\u2026</option>'
    countryData.forEach(function(c) {
      var opt = document.createElement('option')
      opt.value = c.country_code
      opt.textContent = c.country_name
      selCountry.appendChild(opt)
    })
  }

  // ── Config section ───────────────────────────────────────────────────
  document.querySelectorAll('input[name="units"]').forEach(function(r) {
    r.addEventListener('change', function() {
      var unit = document.querySelector('input[name="units"]:checked').value
      document.getElementById('chargeWeightLabel').textContent = 'Charge weight (' + unit + ')'
    })
  })

  document.getElementById('configToggle').addEventListener('click', function() {
    this.classList.toggle('open')
    document.getElementById('configBody').classList.toggle('open')
  })

  // ── Validation helpers ───────────────────────────────────────────────
  function showErr(id, msg) {
    var el  = document.getElementById('err-' + id)
    var inp = document.getElementById(id) || document.querySelector('[name="' + id + '"]')
    if (el)  { el.textContent = msg; el.style.display = 'block' }
    if (inp) inp.classList.add('invalid')
  }
  function clearAllErrors() {
    document.querySelectorAll('.field-error').forEach(function(e) { e.style.display = 'none' })
    document.querySelectorAll('.invalid').forEach(function(e) { e.classList.remove('invalid') })
    document.getElementById('errorBanner').classList.remove('visible')
  }

  // ── Submit ───────────────────────────────────────────────────────────
  document.getElementById('signupForm').addEventListener('submit', async function(e) {
    e.preventDefault()
    clearAllErrors()

    function get(id) { return document.getElementById(id).value.trim() }
    var valid = true

    if (!get('companyName'))  { showErr('companyName',  'Required'); valid = false }
    if (!get('facilityName')) { showErr('facilityName', 'Required'); valid = false }
    if (!get('country'))      { showErr('country',      'Required'); valid = false }
    if (!get('timezone'))     { showErr('timezone',     'Required'); valid = false }
    if (!get('adminName'))    { showErr('adminName',    'Required'); valid = false }
    var email = get('email')
    if (!email || !/^[^\\s@]+@[^\\s@]+\\.[^\\s@]+$/.test(email)) {
      showErr('email', 'Enter a valid email'); valid = false
    }
    var pw = get('password')
    if (!pw || pw.length < 8) {
      showErr('password', 'Min 8 characters'); valid = false
    }
    if (pw !== document.getElementById('confirmPassword').value) {
      showErr('confirmPassword', "Passwords don't match"); valid = false
    }
    if (!valid) return

    var units        = document.querySelector('input[name="units"]:checked').value
    var retentionRaw = parseFloat(document.getElementById('retentionRate').value)
    var payload = {
      company_name:  get('companyName'),
      facility_name: get('facilityName'),
      timezone:      get('timezone'),
      admin_name:    get('adminName'),
      email:         get('email'),
      password:      get('password'),
      country_code:  get('country'),
      plan_id:       selectedPlanId,
      parameters: {
        units: units,
        retention_rate:   isNaN(retentionRaw) ? 0.82 : retentionRaw / 100,
        charge_weight:    parseFloat(document.getElementById('chargeWeight').value)    || 25,
        roast_reset_day:  parseInt(document.getElementById('roastResetDay').value,  10),
        orders_reset_day: parseInt(document.getElementById('ordersResetDay').value, 10),
      },
    }

    var btn = document.getElementById('submitBtn')
    btn.disabled = true
    btn.classList.add('loading')
    btn.querySelector('.btn-text').textContent = 'Creating account\u2026'

    try {
      var res  = await fetch(EDGE_FN_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json', apikey: SUPABASE_ANON_KEY, Authorization: 'Bearer ' + SUPABASE_ANON_KEY },
        body: JSON.stringify(payload),
      })
      var data = await res.json()
      if (!res.ok || !data.success) throw new Error(data.error || 'Server error (' + res.status + ')')

      document.getElementById('formWrap').style.display = 'none'
      document.getElementById('successCard').classList.add('visible')

    } catch (err) {
      var banner = document.getElementById('errorBanner')
      banner.textContent = err.message || 'Something went wrong. Please try again.'
      banner.classList.add('visible')
      btn.disabled = false
      btn.classList.remove('loading')
      btn.querySelector('.btn-text').textContent = 'Create account & start trial'
    }
  })
</script>
</body>
</html>`
}
