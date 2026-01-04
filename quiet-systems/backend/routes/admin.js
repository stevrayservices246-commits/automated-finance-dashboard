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
