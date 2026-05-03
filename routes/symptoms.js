// routes/symptoms.js
const express = require('express');
const { body, validationResult } = require('express-validator');
const { query } = require('../db/pool');

const router = express.Router();
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });
  next();
};

// ── GET /symptoms  ── master list ────────────────────────────
router.get('/', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM symptom ORDER BY symptom_name`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /symptoms/patient/:patientId ─────────────────────────
router.get('/patient/:patientId', async (req, res) => {
  try {
    const { rows } = await query(
      `SELECT ps.id, s.symptom_name, ps.severity, ps.reported_date
       FROM patient_symptom ps
       JOIN symptom s ON ps.symptom_id = s.symptom_id
       WHERE ps.patient_id = $1
       ORDER BY ps.reported_date DESC`,
      [req.params.patientId]
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST /symptoms/log  ── log symptoms for a patient ────────
router.post(
  '/log',
  [
    body('patient_id').notEmpty(),
    body('symptoms').isArray({ min: 1 }).withMessage('At least one symptom required'),
    body('severity').isIn(['Mild', 'Moderate', 'Severe']),
    body('reported_date').optional().isDate(),
  ],
  validate,
  async (req, res) => {
    try {
      const { patient_id, symptoms, severity, reported_date } = req.body;
      const date = reported_date || new Date().toISOString().split('T')[0];

      // Resolve symptom names → IDs (insert if missing)
      const inserted = [];
      for (const name of symptoms) {
        // Upsert symptom
        await query(
          `INSERT INTO symptom (symptom_name) VALUES ($1) ON CONFLICT (symptom_name) DO NOTHING`,
          [name]
        );
        const { rows: sym } = await query(
          `SELECT symptom_id FROM symptom WHERE symptom_name=$1`, [name]
        );
        const symptom_id = sym[0].symptom_id;

        // Upsert patient_symptom
        const { rows } = await query(
          `INSERT INTO patient_symptom (patient_id, symptom_id, severity, reported_date)
           VALUES ($1,$2,$3,$4)
           ON CONFLICT (patient_id, symptom_id, reported_date)
           DO UPDATE SET severity = EXCLUDED.severity
           RETURNING *`,
          [patient_id, symptom_id, severity, date]
        );
        inserted.push(rows[0]);
      }

      res.status(201).json({ success: true, data: inserted });
    } catch (err) {
      res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ── GET /symptoms/frequency  ── top symptoms analytics ───────
router.get('/frequency', async (_req, res) => {
  try {
    const { rows } = await query(
      `SELECT s.symptom_name, COUNT(*) AS count
       FROM patient_symptom ps
       JOIN symptom s ON ps.symptom_id = s.symptom_id
       GROUP BY s.symptom_name
       ORDER BY count DESC
       LIMIT 10`
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
