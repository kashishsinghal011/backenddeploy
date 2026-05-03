// server.js — Disease Risk Prediction & Patient Analytics API
require('dotenv').config();

const express    = require('express');
const cors       = require('cors');
const { initDB } = require('./db/pool');

// ── Routes ────────────────────────────────────────────────────
const patientsRouter  = require('./routes/patients');
const symptomsRouter  = require('./routes/symptoms');
const riskRouter      = require('./routes/risk');
const alertsRouter    = require('./routes/alerts');
const analyticsRouter = require('./routes/analytics');
const lookupRouter    = require('./routes/lookup');

const app  = express();
const PORT = process.env.PORT || 3001;

// ── CORS ──────────────────────────────────────────────────────
const allowedOrigins = (process.env.CORS_ORIGINS || '')
  .split(',')
  .map(s => s.trim())
  .filter(Boolean);

app.use(cors({
  origin: (origin, cb) => {
    // Allow requests with no origin (curl, Postman, same-origin)
    if (!origin || allowedOrigins.includes(origin) || allowedOrigins.includes('*')) {
      cb(null, true);
    } else {
      cb(new Error(`CORS: origin ${origin} not allowed`));
    }
  },
  credentials: true,
}));

// ── Body parsers ──────────────────────────────────────────────
app.use(express.json({ limit: '2mb' }));
app.use(express.urlencoded({ extended: true }));

// ── Request logger (dev) ──────────────────────────────────────
app.use((req, _res, next) => {
  console.log(`${new Date().toISOString()}  ${req.method}  ${req.path}`);
  next();
});

// ── Health check ──────────────────────────────────────────────
app.get('/health', (_req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// ── API Routes ────────────────────────────────────────────────
app.use('/api/patients',  patientsRouter);
app.use('/api/symptoms',  symptomsRouter);
app.use('/api/risk',      riskRouter);
app.use('/api/alerts',    alertsRouter);
app.use('/api/analytics', analyticsRouter);
app.use('/api/lookup',    lookupRouter);

// ── 404 handler ───────────────────────────────────────────────
app.use((_req, res) => {
  res.status(404).json({ success: false, message: 'Route not found' });
});

// ── Global error handler ──────────────────────────────────────
app.use((err, _req, res, _next) => {
  console.error(err.stack);
  res.status(500).json({ success: false, message: err.message || 'Internal server error' });
});

// ── Boot ─────────────────────────────────────────────────────
(async () => {
  try {
    await initDB();
    app.listen(PORT, () => {
      console.log(`\n🏥  Disease Risk API running at http://localhost:${PORT}`);
      console.log(`📋  Endpoints:`);
      console.log(`    GET  /health`);
      console.log(`    ---  Patients  ---`);
      console.log(`    GET  /api/patients`);
      console.log(`    POST /api/patients`);
      console.log(`    GET  /api/patients/:id`);
      console.log(`    PUT  /api/patients/:id`);
      console.log(`    DEL  /api/patients/:id`);
      console.log(`    ---  Symptoms  ---`);
      console.log(`    GET  /api/symptoms`);
      console.log(`    GET  /api/symptoms/patient/:patientId`);
      console.log(`    POST /api/symptoms/log`);
      console.log(`    GET  /api/symptoms/frequency`);
      console.log(`    ---  Risk  ---`);
      console.log(`    POST /api/risk/assess`);
      console.log(`    GET  /api/risk/assessments`);
      console.log(`    GET  /api/risk/high`);
      console.log(`    ---  Alerts  ---`);
      console.log(`    GET  /api/alerts`);
      console.log(`    GET  /api/alerts/count`);
      console.log(`    PATCH /api/alerts/:id/resolve`);
      console.log(`    ---  Analytics  ---`);
      console.log(`    GET  /api/analytics/summary`);
      console.log(`    GET  /api/analytics/risk-breakdown`);
      console.log(`    GET  /api/analytics/age-groups`);
      console.log(`    GET  /api/analytics/symptom-frequency`);
      console.log(`    GET  /api/analytics/monthly-trends`);
      console.log(`    GET  /api/analytics/reports`);
      console.log(`    POST /api/analytics/reports`);
      console.log(`    ---  Lookup  ---`);
      console.log(`    GET  /api/lookup/doctors`);
      console.log(`    GET  /api/lookup/diseases`);
      console.log(`    GET  /api/lookup/symptoms\n`);
    });
  } catch (err) {
    console.error('❌  Failed to start server:', err.message);
    process.exit(1);
  }
})();
