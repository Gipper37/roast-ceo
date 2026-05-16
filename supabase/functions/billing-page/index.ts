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
  <title>RoastOS — Billing Portal</title>
  <style>
    *, *::before, *::after { box-sizing: border-box; margin: 0; padding: 0; }
    :root {
      --brown:  #3e260e;
      --tan:    #d4a96a;
      --cream:  #fdf6ec;
      --muted:  #8a6e5e;
      --error:  #c0392b;
      --border: #e0d0c0;
      --radius: 8px;
    }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', sans-serif;
      background: var(--cream);
      color: var(--brown);
      min-height: 100vh;
      display: flex;
      align-items: center;
      justify-content: center;
      flex-direction: column;
      gap: 16px;
      padding: 40px 16px;
      text-align: center;
    }
    img.logo {
      height: 44px;
      margin-bottom: 8px;
    }
    .spinner {
      width: 36px; height: 36px;
      border: 3px solid rgba(62,38,14,0.15);
      border-top-color: var(--tan);
      border-radius: 50%;
      animation: spin 0.7s linear infinite;
    }
    @keyframes spin { to { transform: rotate(360deg); } }
    h2 { font-size: 1.1rem; font-weight: 600; }
    p  { font-size: 0.85rem; color: var(--muted); }
    .error {
      background: #fdf0ef;
      border: 1.5px solid #f5c6c2;
      border-radius: var(--radius);
      color: var(--error);
      font-size: 0.88rem;
      padding: 12px 18px;
      max-width: 400px;
      display: none;
    }
    .error.visible { display: block; }
  </style>
</head>
<body>
  <img class="logo" src="${logoUrl}" alt="RoastOS" />
  <div class="spinner" id="spinner"></div>
  <h2 id="message">Loading your billing portal…</h2>
  <p>You'll be redirected to Stripe to manage your subscription.</p>
  <div class="error" id="errorBox"></div>

  <script>
    var SUPABASE_URL      = 'https://pwpslalerytymorcodlv.supabase.co'
    var SUPABASE_ANON_KEY = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InB3cHNsYWxlcnl0eW1vcmNvZGx2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE3Njg0MjM3NDcsImV4cCI6MjA4Mzk5OTc0N30.MZsWvHwfhNirxwC4tC6tkiT3_fBn3ZMK0AvjZ0YaaTQ'
    var PORTAL_FN         = SUPABASE_URL + '/functions/v1/create-portal-session'

    var params    = new URLSearchParams(window.location.search)
    var companyId = params.get('company_id') || ''
    var returnUrl = params.get('return_url') || window.location.origin

    async function loadPortal() {
      if (!companyId) {
        showError('Missing company ID. Please return to the app and try again.')
        return
      }

      try {
        var res = await fetch(PORTAL_FN, {
          method: 'POST',
          headers: {
            'Content-Type': 'application/json',
            apikey: SUPABASE_ANON_KEY,
            Authorization: 'Bearer ' + SUPABASE_ANON_KEY,
          },
          body: JSON.stringify({ company_id: companyId, return_url: returnUrl }),
        })
        var data = await res.json()
        if (!res.ok || !data.url) throw new Error(data.error || 'Could not open billing portal')
        window.location.href = data.url

      } catch (err) {
        showError(err.message || 'Something went wrong. Please try again.')
      }
    }

    function showError(msg) {
      document.getElementById('spinner').style.display = 'none'
      document.getElementById('message').textContent = 'Unable to open billing portal'
      var box = document.getElementById('errorBox')
      box.textContent = msg
      box.classList.add('visible')
    }

    loadPortal()
  </script>
</body>
</html>`
}
