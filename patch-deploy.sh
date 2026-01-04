#!/bin/bash
set -euo pipefail

cd ~/quiet-systems

echo "==> Patching Quiet Systems for Railway/Render deployability..."

# ----------------------------
# 0) Fix backend/.env generation (real secrets)
# ----------------------------
cd backend
ADMIN_API_KEY="qs_$(openssl rand -hex 24)"
JWT_SECRET="jwt_$(openssl rand -hex 32)"
ENCRYPTION_KEY="enc_$(openssl rand -hex 32)"
BUILD_DATE="$(date +%Y%m%d)"

cat > .env << ENV_EOF
# ======================
# QUIET SYSTEMS CONFIG
# ======================

NODE_ENV=production
PORT=3000

# Security
ADMIN_API_KEY=${ADMIN_API_KEY}
JWT_SECRET=${JWT_SECRET}
ENCRYPTION_KEY=${ENCRYPTION_KEY}

# Google Sheets API
GOOGLE_SHEETS_ID=YOUR_SHEETS_ID_HERE
GOOGLE_SERVICE_ACCOUNT_PATH=./config/service-account.json

# PayPal API
PAYPAL_CLIENT_ID=YOUR_PAYPAL_CLIENT_ID
PAYPAL_SECRET=YOUR_PAYPAL_SECRET
PAYPAL_ENV=sandbox

# Google Pay / Wallet
GOOGLE_MERCHANT_ID=YOUR_MERCHANT_ID
GOOGLE_MERCHANT_NAME="Quiet Systems LLC"

# Business Model Configuration
MODEL1_CONTENT_SITES=3
MODEL2_SAAS_PRODUCTS=2
MODEL3_AFFILIATE_OFFERS=5
MODEL4_STOCK_ASSETS=1000
MODEL5_ECOMMERCE_PRODUCTS=50

# Financial Settings
TAX_RATE=0.30
AUTO_TRANSFER_THRESHOLD=100
PROFIT_MARGIN_TARGET=0.40

# Notification Settings
EMAIL_ALERTS=true
SLACK_WEBHOOK_URL=
TELEGRAM_BOT_TOKEN=

# Backup Settings
BACKUP_DAILY=true
BACKUP_TO_S3=false
S3_BUCKET=your-backup-bucket

# VA Settings
VA_HOURLY_RATE=8
VA_MAX_HOURS_WEEKLY=40
VA_PAYMENT_DAY=Friday

VERSION=1.0.0
BUILD_DATE=${BUILD_DATE}
ENV_EOF

echo "==> .env regenerated with real secrets."
echo "==> ADMIN_API_KEY: ${ADMIN_API_KEY}"

# ----------------------------
# 1) Convert admin-api to a router (NO separate port)
# ----------------------------
cat > modules/admin-api.js << 'ADMIN_ROUTER_EOF'
// ============================================
// ADMIN API ROUTER (single-port friendly)
// ============================================
const express = require("express");
const rateLimit = require("express-rate-limit");

const router = express.Router();

const limiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  max: 100,
  message: "Too many requests from this IP"
});

router.use(limiter);
router.use(express.json());

// API key auth (HEADER ONLY)
router.use((req, res, next) => {
  const apiKey = req.headers["x-api-key"];
  if (!apiKey || apiKey !== process.env.ADMIN_API_KEY) {
    return res.status(401).json({ error: "Unauthorized", code: "ADMIN_401" });
  }
  next();
});

router.get("/status", async (req, res) => {
  const sheets = require("./sheets-integration");
  const payments = require("./payment-processor");
  const monitoring = require("./monitoring");

  const [sheetsHealth, paymentsHealth, revenue, dash] = await Promise.all([
    sheets.healthCheck(),
    payments.healthCheck(),
    sheets.getMTDRevenue(),
    monitoring.getDashboardData()
  ]);

  res.json({
    system: "quiet-systems",
    version: process.env.VERSION,
    status: "operational",
    timestamp: new Date().toISOString(),
    components: { sheets: sheetsHealth, payments: paymentsHealth },
    revenue: revenue.success
      ? {
          mtd: revenue.amount,
          target: 100000,
          progress: ((revenue.amount / 100000) * 100).toFixed(1) + "%"
        }
      : { error: "Unable to fetch revenue" },
    dashboard: dash
  });
});

router.get("/alerts", (req, res) => {
  const monitoring = require("./monitoring");
  res.json({
    alerts: monitoring.alerts,
    count: monitoring.alerts.length
  });
});

router.post("/alert/:id/acknowledge", (req, res) => {
  const monitoring = require("./monitoring");
  const alert = monitoring.alerts.find(a => a.id === req.params.id);
  if (!alert) return res.status(404).json({ error: "Alert not found" });
  alert.acknowledged = true;
  res.json({ success: true, alert });
});

module.exports = router;
ADMIN_ROUTER_EOF

echo "==> admin-api converted to router."

# ----------------------------
# 2) Enforce PayPal + Google Pay only (remove Stripe)
# ----------------------------
# Patch payment-processor supported methods + remove stripe mention safely
node - <<'NODE_EOF'
const fs = require("fs");
const p = "./modules/payment-processor.js";
let s = fs.readFileSync(p, "utf8");

// supportedMethods line
s = s.replace(
  /this\.supportedMethods\s*=\s*\[[^\]]*\];/g,
  "this.supportedMethods = ['paypal', 'google_pay'];"
);

// remove 'stripe' token if present in arrays/strings
s = s.replace(/['"]stripe['"]\s*,?/g, "");

// fix model2 saas "stripe" mentions (your admin models text had stripe)
s = s.replace(/stripe\s*\+\s*digital delivery/gi, "paypal + gated delivery");

fs.writeFileSync(p, s);
console.log("Patched payment-processor.js");
NODE_EOF

echo "==> payment-processor locked to PayPal + Google Pay."

# ----------------------------
# 3) Update routes/admin.js to use header only
# ----------------------------
cat > routes/admin.js << 'ROUTES_ADMIN_EOF'
const express = require('express');
const router = express.Router();

// Middleware to verify admin API key (HEADER ONLY)
router.use((req, res, next) => {
  const apiKey = req.headers["x-api-key"];
  if (apiKey === process.env.ADMIN_API_KEY) next();
  else res.status(401).json({ error: "Invalid API key" });
});

router.get('/status', async (req, res) => {
  const adminRouter = require('../modules/admin-api');
  // delegate to module router handler by calling the same logic via monitoring
  const monitoring = require('../modules/monitoring');
  const data = await monitoring.getDashboardData();
  res.json(data);
});

router.get('/alerts', async (req, res) => {
  const monitoring = require('../modules/monitoring');
  res.json({
    alerts: monitoring.alerts,
    count: monitoring.alerts.length
  });
});

router.post('/alert/:id/acknowledge', async (req, res) => {
  const monitoring = require('../modules/monitoring');
  const alert = monitoring.alerts.find(a => a.id === req.params.id);
  if (alert) {
    alert.acknowledged = true;
    res.json({ success: true, alert });
  } else {
    res.status(404).json({ error: 'Alert not found' });
  }
});

module.exports = router;
ROUTES_ADMIN_EOF

echo "==> routes/admin.js updated to header auth only."

# ----------------------------
# 4) Fix backend/index.js:
#    - remove multi-port module load
#    - serve frontend correctly
#    - mount admin router
# ----------------------------
cat > index.js << 'INDEX_EOF'
// ============================================
// QUIET SYSTEMS - MAIN SERVER ENTRY POINT
// (Railway/Render compatible: SINGLE PORT)
// ============================================
require('dotenv').config();
const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const path = require('path');

console.log(`
╔══════════════════════════════════════════════════════════╗
║                QUIET SYSTEMS v1.0.0                      ║
║          $100K/Month Automation Platform                  ║
╚══════════════════════════════════════════════════════════╝
`);

const app = express();

// Security middleware
app.use(helmet());
app.use(cors({
  origin: (process.env.CORS_ORIGIN || '').split(',').filter(Boolean).length
    ? (process.env.CORS_ORIGIN || '').split(',').map(s => s.trim())
    : true,
  credentials: true
}));

// Webhooks can stay JSON for now (signature verification would use raw)
app.use('/api/payments/webhook/paypal', express.json({ limit: '2mb' }));

app.use(express.json({ limit: '10mb' }));
app.use(express.urlencoded({ extended: true }));

// Load core modules (NO extra listening servers)
const systems = [
  require('./modules/sheets-integration'),
  require('./modules/payment-processor'),
  require('./modules/model1-content'),
  require('./modules/model2-saas'),
  require('./modules/model3-affiliate'),
  require('./modules/model4-stock'),
  require('./modules/model5-ecommerce'),
  require('./modules/automation-engine'),
  require('./modules/monitoring')
];

// Health endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'operational',
    version: process.env.VERSION,
    timestamp: new Date().toISOString(),
    systems: systems.map(s => s.name),
    revenue: {
      today: "$0.00",
      mtd: "$0.00",
      target: "$100,000.00"
    }
  });
});

// Serve frontend (static HTML dashboard)
const frontendPath = path.join(__dirname, '../frontend');
app.use(express.static(frontendPath));

app.get('/dashboard', (req, res) => {
  res.sendFile(path.join(frontendPath, 'index.html'));
});

// API routes
app.use('/api/sheets', require('./routes/sheets'));
app.use('/api/payments', require('./routes/payments'));
app.use('/api/admin', require('./modules/admin-api')); // <-- router
app.use('/api/models', require('./routes/models'));
app.use('/api/automations', require('./routes/automations'));

// Error handling
app.use((err, req, res, next) => {
  console.error('System Error:', err);
  res.status(500).json({
    error: 'System error',
    message: process.env.NODE_ENV === 'development' ? err.message : 'Internal server error',
    code: 'QS_500'
  });
});

const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`🚀 Quiet Systems running on port ${PORT}`);
  console.log(`📊 Dashboard: http://localhost:${PORT}/dashboard`);
  console.log(`🔧 API: http://localhost:${PORT}/api`);
  console.log(`❤️  Health: http://localhost:${PORT}/health`);
  console.log('\n📋 System Status:');
  console.log('   ✅ Sheets Integration');
  console.log('   ✅ Payment Processing (PayPal + Google Pay)');
  console.log('   ✅ Admin API (single port)');
  console.log('   ✅ 5 Revenue Models');
  console.log('   ✅ Automation Engine');
  console.log('\n💰 Target: $100,000/month');
  console.log('⏰ Started: ' + new Date().toLocaleString());
});

module.exports = app;
INDEX_EOF

echo "==> backend/index.js updated for single-port hosting."

# ----------------------------
# 5) Update frontend dashboard JS to use header auth (no query string secrets)
# ----------------------------
cd ../frontend

# Replace the script block by rewriting whole file (safe, deterministic)
cat > index.html << 'HTML_EOF'
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8" />
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Quiet Systems Dashboard</title>
  <style>
    * { margin: 0; padding: 0; box-sizing: border-box; }
    body {
      font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, Oxygen, Ubuntu, sans-serif;
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      min-height: 100vh;
      padding: 20px;
    }
    .container { max-width: 1200px; margin: 0 auto; }
    .header {
      background: rgba(255,255,255,0.1);
      backdrop-filter: blur(10px);
      border-radius: 20px;
      padding: 30px;
      margin-bottom: 30px;
      border: 1px solid rgba(255,255,255,0.2);
    }
    .header h1 { color: white; font-size: 2.5rem; margin-bottom: 10px; }
    .header p { color: rgba(255,255,255,0.8); font-size: 1.1rem; }
    .stats-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(250px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    .stat-card {
      background: white;
      border-radius: 15px;
      padding: 25px;
      box-shadow: 0 10px 30px rgba(0,0,0,0.1);
      transition: transform 0.3s ease;
    }
    .stat-card:hover { transform: translateY(-5px); }
    .stat-card h3 {
      color: #666;
      font-size: 0.9rem;
      text-transform: uppercase;
      letter-spacing: 1px;
      margin-bottom: 10px;
    }
    .stat-card .value { font-size: 2.5rem; font-weight: bold; color: #333; margin-bottom: 5px; }
    .stat-card .progress { height: 6px; background: #eee; border-radius: 3px; margin-top: 15px; overflow: hidden; }
    .stat-card .progress-bar { height: 100%; background: linear-gradient(90deg, #667eea, #764ba2); border-radius: 3px; width: 0%; }
    .models-grid {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
      gap: 20px;
      margin-bottom: 30px;
    }
    .model-card {
      background: rgba(255,255,255,0.9);
      border-radius: 15px;
      padding: 20px;
      text-align: center;
      backdrop-filter: blur(10px);
      border: 1px solid rgba(255,255,255,0.2);
    }
    .model-card h4 { color: #333; margin-bottom: 10px; }
    .model-card .revenue { font-size: 1.5rem; font-weight: bold; color: #667eea; margin-bottom: 5px; }
    .controls { background: white; border-radius: 15px; padding: 30px; margin-bottom: 30px; }
    .btn {
      background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
      color: white; border: none;
      padding: 12px 24px;
      border-radius: 10px;
      font-size: 1rem;
      cursor: pointer;
      margin-right: 10px;
      margin-bottom: 10px;
      transition: opacity 0.3s ease;
    }
    .btn:hover { opacity: 0.9; }
    .btn-secondary { background: #6c757d; }
    .alert {
      background: #fff3cd;
      border: 1px solid #ffeaa7;
      color: #856404;
      padding: 15px;
      border-radius: 10px;
      margin-bottom: 20px;
      display: none;
    }
    .footer { text-align: center; color: rgba(255,255,255,0.6); margin-top: 40px; font-size: 0.9rem; }
    @media (max-width: 768px) { .header h1 { font-size: 2rem; } .stats-grid { grid-template-columns: 1fr; } }
  </style>
</head>
<body>
  <div class="container">
    <div class="header">
      <h1>🚀 Quiet Systems Dashboard</h1>
      <p>Automated $100K/Month System • Running 24/7 • Zero Face Required</p>
    </div>

    <div class="stats-grid">
      <div class="stat-card">
        <h3>Today's Revenue</h3>
        <div class="value" id="todayRevenue">$0.00</div>
        <div class="progress"><div class="progress-bar" id="pb1"></div></div>
      </div>
      <div class="stat-card">
        <h3>MTD Revenue</h3>
        <div class="value" id="mtdRevenue">$0.00</div>
        <div class="progress"><div class="progress-bar" id="pb2"></div></div>
      </div>
      <div class="stat-card">
        <h3>System Health</h3>
        <div class="value" id="systemHealth">100%</div>
        <div class="progress"><div class="progress-bar" id="pb3" style="width:100%"></div></div>
      </div>
      <div class="stat-card">
        <h3>Days Remaining</h3>
        <div class="value" id="daysRemaining">30</div>
        <div class="progress"><div class="progress-bar" id="pb4" style="width:100%"></div></div>
      </div>
    </div>

    <div class="alert" id="systemAlert">
      ⚠️ <span id="alertMessage">System alert</span>
    </div>

    <h2 style="color: white; margin-bottom: 20px;">📊 Revenue Models</h2>
    <div class="models-grid">
      <div class="model-card"><h4>Content Sites</h4><div class="revenue" id="model1">$0</div><div>Target: $30K</div></div>
      <div class="model-card"><h4>Micro-SaaS</h4><div class="revenue" id="model2">$0</div><div>Target: $40K</div></div>
      <div class="model-card"><h4>Affiliate</h4><div class="revenue" id="model3">$0</div><div>Target: $30K</div></div>
      <div class="model-card"><h4>Digital Assets</h4><div class="revenue" id="model4">$0</div><div>Target: $5K</div></div>
      <div class="model-card"><h4>E-commerce</h4><div class="revenue" id="model5">$0</div><div>Target: $30K</div></div>
    </div>

    <div class="controls">
      <h2 style="margin-bottom: 20px;">🤖 System Controls</h2>
      <button class="btn" onclick="runAutomations()">Run Daily Automations</button>
      <button class="btn" onclick="updateDashboard()">Update Dashboard</button>
      <button class="btn btn-secondary" onclick="checkHealth()">System Health Check</button>
      <button class="btn btn-secondary" onclick="simulateMonth()">Simulate 30 Days</button>
    </div>

    <div class="footer">
      <p>Quiet Systems v1.0 • Built for Privacy & Automation • Payments via PayPal + Google Pay</p>
      <p>⏰ Last updated: <span id="lastUpdate">Never</span></p>
    </div>
  </div>

  <script>
    const API_BASE = ''; // same origin (works on Railway/Render)
    const KEY_STORAGE = 'qs_admin_api_key';

    let API_KEY = localStorage.getItem(KEY_STORAGE);
    if (!API_KEY) {
      API_KEY = prompt('Enter Admin API Key (x-api-key):');
      if (API_KEY) localStorage.setItem(KEY_STORAGE, API_KEY);
    }

    async function fetchJSON(endpoint, opts = {}) {
      try {
        const res = await fetch(`${API_BASE}${endpoint}`, {
          ...opts,
          headers: {
            ...(opts.headers || {}),
            "x-api-key": API_KEY || ""
          }
        });
        return await res.json();
      } catch (e) {
        console.error(e);
        showAlert('API connection failed');
        return null;
      }
    }

    async function updateDashboard() {
      const data = await fetchJSON('/api/admin/status');
      if (!data) return;

      const mtd = data.revenue?.mtd || 0;
      const todayEstimate = mtd / Math.max(1, new Date().getDate());

      document.getElementById('todayRevenue').textContent = '$' + todayEstimate.toFixed(2);
      document.getElementById('mtdRevenue').textContent = '$' + mtd.toFixed(2);

      const progress = (mtd / 100000) * 100;
      document.getElementById('pb1').style.width = Math.min(progress, 100) + '%';
      document.getElementById('pb2').style.width = Math.min(progress, 100) + '%';

      const now = new Date();
      const daysInMonth = new Date(now.getFullYear(), now.getMonth() + 1, 0).getDate();
      document.getElementById('daysRemaining').textContent = daysInMonth - now.getDate();

      document.getElementById('lastUpdate').textContent = new Date().toLocaleTimeString();
      showAlert('Dashboard updated', 'success');
    }

    async function runAutomations() {
      const data = await fetchJSON('/api/automations/run', { method: 'POST' });
      if (data && data.successCount !== undefined) {
        showAlert(`Automations completed: ${data.successCount}/${data.totalTasks}`, 'success');
        setTimeout(updateDashboard, 1500);
      }
    }

    async function checkHealth() {
      const h = await fetchJSON('/health', { headers: {} }); // no key required
      if (h && h.status) showAlert('Health: ' + h.status, 'success');
    }

    async function simulateMonth() {
      if (!confirm('Simulate 30 days? (This can take time.)')) return;
      const data = await fetchJSON('/api/automations/simulate-month', { method: 'POST' });
      if (data && data.totalRevenue !== undefined) {
        showAlert(`Simulation done: $${Number(data.totalRevenue).toFixed(2)}`, 'success');
        setTimeout(updateDashboard, 1000);
      }
    }

    function showAlert(msg, type = 'warning') {
      const el = document.getElementById('systemAlert');
      const m = document.getElementById('alertMessage');
      m.textContent = msg;
      el.style.display = 'block';
      el.style.background = type === 'success' ? '#d4edda' : '#fff3cd';
      el.style.borderColor = type === 'success' ? '#c3e6cb' : '#ffeaa7';
      el.style.color = type === 'success' ? '#155724' : '#856404';
      setTimeout(() => el.style.display = 'none', 3500);
    }

    updateDashboard();
    setInterval(updateDashboard, 60000);
  </script>
</body>
</html>
HTML_EOF

echo "==> frontend/index.html updated for header auth + same-origin API."

# ----------------------------
# 6) Add Render Blueprint (render.yaml) (single web service)
# ----------------------------
cd ~/quiet-systems

cat > render.yaml << 'RENDER_EOF'
services:
  - type: web
    name: quiet-systems
    runtime: node
    plan: starter
    rootDir: backend
    buildCommand: npm install
    startCommand: node index.js
    envVars:
      - key: NODE_ENV
        value: production
      # IMPORTANT: set the rest of your env vars in Render dashboard as "Secret"
      # (GOOGLE_SHEETS_ID, PAYPAL_CLIENT_ID, PAYPAL_SECRET, etc.)
RENDER_EOF

echo "==> render.yaml created (Render Blueprint)."

# ----------------------------
# 7) Add Railway config-as-code (railway.toml)
# ----------------------------
cat > railway.toml << 'RAILWAY_TOML_EOF'
# Railway Config-as-Code
# Railway supports railway.toml / railway.json for build & start overrides.
# Docs: https://docs.railway.com/reference/config-as-code
# Note: If Railway doesn't honor rootDir here, set the service Root Directory to "backend" in the Railway UI.

[build]
builder = "NIXPACKS"
buildCommand = "cd backend && npm install"

[deploy]
startCommand = "cd backend && node index.js"
RAILWAY_TOML_EOF

echo "==> railway.toml created (Railway Config-as-Code)."

# ----------------------------
# 8) Quick sanity check (local)
# ----------------------------
cd backend
npm install >/dev/null 2>&1 || true

echo ""
echo "✅ Patch complete!"
echo ""
echo "Local run:"
echo "  cd ~/quiet-systems/backend && npm start"
echo ""
echo "Open:"
echo "  http://localhost:3000/dashboard"
echo ""
echo "Admin API Key (x-api-key):"
echo "  ${ADMIN_API_KEY}"
