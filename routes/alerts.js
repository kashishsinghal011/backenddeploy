// routes/alerts.js
const express = require('express');
const { body, validationResult } = require('express-validator');
const { query } = require('../db/pool');

const router = express.Router();

// ── GET /alerts  ── all active alerts ────────────────────────
router.get('/', async (req, res) => {
  try {
    const status = req.query.status || 'Active';
    const { rows } = await query(
      `SELECT a.*, p.name AS patient_name
       FROM alert a
       JOIN patient p ON a.patient_id = p.patient_id
       WHERE a.status = $1
       ORDER BY a.triggered_at DESC`,
      [status]
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /alerts/count ─────────────────────────────────────────
router.get('/count', async (_req, res) => {
  try {
    const { rows } = await query(
      `SELECT COUNT(*) AS count FROM alert WHERE status='Active'`
    );
    res.json({ success: true, count: Number(rows[0].count) });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── PATCH /alerts/:id/resolve ─────────────────────────────────
router.patch('/:id/resolve', async (req, res) => {
  try {
    const { rows } = await query(
      `UPDATE alert SET status='Resolved', resolved_at=NOW()
       WHERE alert_id=$1 RETURNING *`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, message: 'Alert not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── DELETE /alerts/:id ────────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    await query(`DELETE FROM alert WHERE alert_id=$1`, [req.params.id]);
    res.json({ success: true, message: 'Alert dismissed' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
