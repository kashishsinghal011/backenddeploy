// routes/lookup.js — doctors, diseases (reference data)
const express = require('express');
const { query } = require('../db/pool');

const router = express.Router();

// ── GET /lookup/doctors ───────────────────────────────────────
router.get('/doctors', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM doctor ORDER BY name`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /lookup/diseases ──────────────────────────────────────
router.get('/diseases', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM disease ORDER BY name`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /lookup/symptoms ──────────────────────────────────────
router.get('/symptoms', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM symptom ORDER BY symptom_name`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
