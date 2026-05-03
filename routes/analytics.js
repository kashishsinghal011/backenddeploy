// routes/analytics.js
const express = require('express');
const { body, validationResult } = require('express-validator');
const { query } = require('../db/pool');

const router = express.Router();
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });
  next();
};

// ── GET /analytics/summary ────────────────────────────────────
router.get('/summary', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM vw_analytics_summary`);
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /analytics/risk-breakdown ────────────────────────────
router.get('/risk-breakdown', async (_req, res) => {
  try {
    const { rows } = await query(
      `SELECT risk_level, COUNT(*) AS count
       FROM patient
       GROUP BY risk_level
       ORDER BY CASE risk_level
         WHEN 'Critical' THEN 1
         WHEN 'High'     THEN 2
         WHEN 'Medium'   THEN 3
         ELSE 4
       END`
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /analytics/age-groups ─────────────────────────────────
router.get('/age-groups', async (_req, res) => {
  try {
    const { rows } = await query(
      `SELECT
         CASE
           WHEN EXTRACT(YEAR FROM AGE(dob)) < 30 THEN '0-29'
           WHEN EXTRACT(YEAR FROM AGE(dob)) < 45 THEN '30-44'
           WHEN EXTRACT(YEAR FROM AGE(dob)) < 60 THEN '45-59'
           ELSE '60+'
         END AS age_group,
         COUNT(*) AS count
       FROM patient
       GROUP BY age_group
       ORDER BY age_group`
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /analytics/symptom-frequency ─────────────────────────
router.get('/symptom-frequency', async (_req, res) => {
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

// ── GET /analytics/disease-category ──────────────────────────
router.get('/disease-category', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM vw_disease_by_category`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /analytics/monthly-trends  (last 6 months) ───────────
router.get('/monthly-trends', async (_req, res) => {
  try {
    const { rows } = await query(
      `SELECT
         TO_CHAR(DATE_TRUNC('month', created_at), 'Mon') AS month,
         DATE_TRUNC('month', created_at) AS month_date,
         COUNT(*) AS new_patients,
         COUNT(CASE WHEN risk_level IN ('High','Critical') THEN 1 END) AS high_risk_count
       FROM patient
       WHERE created_at >= NOW() - INTERVAL '6 months'
       GROUP BY DATE_TRUNC('month', created_at)
       ORDER BY month_date`
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /analytics/top-symptom ───────────────────────────────
router.get('/top-symptom', async (_req, res) => {
  try {
    const { rows } = await query(
      `SELECT s.symptom_name, COUNT(*) AS count
       FROM patient_symptom ps
       JOIN symptom s ON ps.symptom_id = s.symptom_id
       GROUP BY s.symptom_name
       ORDER BY count DESC LIMIT 1`
    );
    res.json({ success: true, data: rows[0] || null });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ─────────────────────────────────────────────────────────────
//  REPORTS
// ─────────────────────────────────────────────────────────────

// ── GET /analytics/reports ───────────────────────────────────
router.get('/reports', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM report ORDER BY generated_at DESC`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST /analytics/reports  ── generate a report ────────────
router.post(
  '/reports',
  [
    body('type').isIn(['Disease Trend', 'High Risk', 'Demographics', 'Symptom Analysis'])
  ],
  validate,
  async (req, res) => {
    try {
      const { type } = req.body;

      // Build a dynamic summary using live data
      let summary = '';
      if (type === 'Disease Trend') {
        const { rows: p } = await query(`SELECT COUNT(*) AS c FROM patient`);
        const { rows: h } = await query(
          `SELECT COUNT(*) AS c FROM risk_assessment WHERE risk_level IN ('High','Critical')`
        );
        summary = `Analysed ${p[0].c} patients. ${h[0].c} high/critical risk assessments recorded.`;
      } else if (type === 'High Risk') {
        const { rows: a } = await query(`SELECT COUNT(*) AS c FROM alert WHERE status='Active'`);
        const { rows: s } = await query(
          `SELECT ROUND(AVG(risk_score)) AS avg FROM risk_assessment`
        );
        summary = `${a[0].c} active alerts. Average risk score: ${s[0].avg ?? 0}/100.`;
      } else if (type === 'Demographics') {
        const { rows: p } = await query(`SELECT COUNT(*) AS c FROM patient`);
        summary = `${p[0].c} patients registered. Age & gender distributions analysed.`;
      } else {
        const { rows: u } = await query(`SELECT COUNT(DISTINCT symptom_id) AS c FROM patient_symptom`);
        summary = `${u[0].c} unique symptoms reported across all patients.`;
      }

      const { rows } = await query(
        `INSERT INTO report (report_type, summary) VALUES ($1,$2) RETURNING *`,
        [type, summary]
      );
      res.status(201).json({ success: true, data: rows[0] });
    } catch (err) {
      res.status(500).json({ success: false, message: err.message });
    }
  }
);

module.exports = router;
