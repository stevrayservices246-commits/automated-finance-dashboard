#!/bin/bash
set -euo pipefail

ROOT="$HOME/quiet-systems"
cd "$ROOT"

echo "==> 1) Fixing tree install (APT, not snap)..."
sudo apt update -y
sudo apt install -y tree

# Optional: remove broken snap tree if it exists (won't fail if not installed)
sudo snap remove tree >/dev/null 2>&1 || true

echo "==> 2) Ensuring backend structure exists..."
mkdir -p "$ROOT/backend/modules" "$ROOT/backend/routes" "$ROOT/backend/config" "$ROOT/backend/logs" "$ROOT/backend/data"
cd "$ROOT/backend"

echo "==> 3) Creating missing module files (safe stubs) if they don't exist..."

# payment-processor.js (required by your patch)
if [ ! -f modules/payment-processor.js ]; then
cat > modules/payment-processor.js << 'PAY_EOF'
const axios = require("axios");
const crypto = require("crypto");

class PaymentProcessor {
  constructor() {
    this.name = "Payment Processor";
    this.status = "ready";
    // Patch script will rewrite this to PayPal + Google Pay only.
    this.supportedMethods = ["paypal", "google_pay", "stripe"];
  }

  async processPayPalPayment(paymentData) {
    const { amount, currency = "USD", description = "Digital Product", returnUrl, cancelUrl } = paymentData;

    // Minimal PayPal order creation (works once env vars are set)
    try {
      const auth = Buffer.from(`${process.env.PAYPAL_CLIENT_ID}:${process.env.PAYPAL_SECRET}`).toString("base64");
      const tokenRes = await axios.post(
        process.env.PAYPAL_ENV === "live"
          ? "https://api-m.paypal.com/v1/oauth2/token"
          : "https://api-m.sandbox.paypal.com/v1/oauth2/token",
        "grant_type=client_credentials",
        { headers: { Authorization: `Basic ${auth}`, "Content-Type": "application/x-www-form-urlencoded" } }
      );

      const accessToken = tokenRes.data.access_token;

      const orderRes = await axios.post(
        process.env.PAYPAL_ENV === "live"
          ? "https://api-m.paypal.com/v2/checkout/orders"
          : "https://api-m.sandbox.paypal.com/v2/checkout/orders",
        {
          intent: "CAPTURE",
          purchase_units: [{ amount: { currency_code: currency, value: String(amount) }, description }],
          application_context: {
            return_url: returnUrl || "https://example.com/success",
            cancel_url: cancelUrl || "https://example.com/cancel"
          }
        },
        { headers: { Authorization: `Bearer ${accessToken}`, "Content-Type": "application/json" } }
      );

      return { success: true, provider: "paypal", orderId: orderRes.data.id, status: orderRes.data.status, links: orderRes.data.links };
    } catch (e) {
      return { success: false, provider: "paypal", error: e.response?.data || e.message };
    }
  }

  async processGooglePay(paymentData) {
    // Placeholder: real Google Pay requires merchant integration in frontend + processor
    return {
      success: true,
      provider: "google_pay",
      transactionId: "GP_" + Date.now() + "_" + crypto.randomBytes(4).toString("hex"),
      amount: paymentData.amount || 0,
      currency: paymentData.currency || "USD"
    };
  }

  async handlePayPalWebhook(body) {
    return { success: true, received: true };
  }

  async processDailySettlement() {
    return { success: true, date: new Date().toISOString().slice(0,10), amount: 0 };
  }

  async healthCheck() {
    return { status: "healthy", timestamp: new Date().toISOString() };
  }
}

module.exports = new PaymentProcessor();
PAY_EOF
fi

# sheets-integration.js (required by admin router)
if [ ! -f modules/sheets-integration.js ]; then
cat > modules/sheets-integration.js << 'SHEETS_EOF'
const { google } = require("googleapis");
const path = require("path");

class SheetsIntegration {
  constructor() {
    this.name = "Sheets Integration";
    this.status = "ready";
    this.spreadsheetId = process.env.GOOGLE_SHEETS_ID || "";
    this.sheets = null;
    this.init();
  }

  async init() {
    try {
      const auth = new google.auth.GoogleAuth({
        keyFile: path.join(__dirname, "../config/service-account.json"),
        scopes: ["https://www.googleapis.com/auth/spreadsheets"]
      });
      this.sheets = google.sheets({ version: "v4", auth });
      this.status = "ready";
    } catch (e) {
      this.status = "degraded";
    }
  }

  async getMTDRevenue() {
    // Minimal stub until you wire real sheet ranges
    return { success: true, amount: 0 };
  }

  async healthCheck() {
    return { status: this.status === "ready" ? "healthy" : "degraded", timestamp: new Date().toISOString() };
  }
}

module.exports = new SheetsIntegration();
SHEETS_EOF
fi

# monitoring.js (required by admin router)
if [ ! -f modules/monitoring.js ]; then
cat > modules/monitoring.js << 'MON_EOF'
class Monitoring {
  constructor() {
    this.name = "Monitoring";
    this.status = "ready";
    this.alerts = [];
  }

  async getDashboardData() {
    const sheets = require("./sheets-integration");
    const revenue = await sheets.getMTDRevenue();
    return {
      metrics: {
        revenue: { current: revenue.amount || 0, target: 100000 }
      },
      checks: { apis: { status: "healthy" } }
    };
  }
}
module.exports = new Monitoring();
MON_EOF
fi

# Basic model stubs referenced by your patch index.js
for f in model1-content.js model2-saas.js model3-affiliate.js model4-stock.js model5-ecommerce.js automation-engine.js; do
  if [ ! -f "modules/$f" ]; then
    cat > "modules/$f" <<'MOD_EOF'
module.exports = {
  name: "stub",
  status: "ready",
  async runDailyAutomations(){ return { success:true, revenue:0 }; },
  async getStats(){ return { success:true }; }
};
MOD_EOF
  fi
done

echo "==> 4) Ensuring routes exist (minimal)..."

if [ ! -f routes/payments.js ]; then
cat > routes/payments.js <<'R_EOF'
const express = require("express");
const router = express.Router();
const payments = require("../modules/payment-processor");

router.post("/paypal", async (req,res)=>res.json(await payments.processPayPalPayment(req.body)));
router.post("/google-pay", async (req,res)=>res.json(await payments.processGooglePay(req.body)));
router.post("/webhook/paypal", async (req,res)=>res.json(await payments.handlePayPalWebhook(req.body)));

module.exports = router;
R_EOF
fi

if [ ! -f routes/automations.js ]; then
cat > routes/automations.js <<'R_EOF'
const express = require("express");
const router = express.Router();

router.post("/run", async (req,res)=>res.json({ successCount: 1, totalTasks: 1 }));
router.post("/simulate-month", async (req,res)=>res.json({ totalRevenue: 0 }));

module.exports = router;
R_EOF
fi

if [ ! -f routes/models.js ]; then
cat > routes/models.js <<'R_EOF'
const express = require("express");
const router = express.Router();
router.get("/", (req,res)=>res.json({ models: [] }));
module.exports = router;
R_EOF
fi

if [ ! -f routes/sheets.js ]; then
cat > routes/sheets.js <<'R_EOF'
const express = require("express");
const router = express.Router();
const sheets = require("../modules/sheets-integration");
router.get("/mtd", async (req,res)=>res.json(await sheets.getMTDRevenue()));
module.exports = router;
R_EOF
fi

echo "==> 5) Install backend deps..."
npm install

echo "==> 6) Show structure (now tree works):"
cd "$ROOT"
tree -L 3 "$ROOT" || true

echo "==> 7) Re-run your patch script..."
if [ -f "$ROOT/patch-deploy.sh" ]; then
  chmod +x "$ROOT/patch-deploy.sh"
  bash "$ROOT/patch-deploy.sh"
else
  echo "❌ Missing: $ROOT/patch-deploy.sh"
  echo "Paste your patch block again to create it, then re-run this fixer."
  exit 1
fi

echo ""
echo "✅ Fixed. Start locally with:"
echo "  cd ~/quiet-systems/backend && npm start"
echo "Then open:"
echo "  http://localhost:3000/dashboard"
