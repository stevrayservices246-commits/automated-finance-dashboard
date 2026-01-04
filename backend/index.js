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
