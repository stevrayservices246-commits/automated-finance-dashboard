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
