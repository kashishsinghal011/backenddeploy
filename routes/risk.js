// routes/risk.js
const express = require('express');
const { body, validationResult } = require('express-validator');
const { query } = require('../db/pool');

const router = express.Router();
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty()) return res.status(400).json({ success: false, errors: errors.array() });
  next();
};

// ── POST /risk/assess  ── run risk scoring via DB function ────
router.post(
  '/assess',
  [
    body('patient_id').notEmpty(),
    body('age').isInt({ min: 0, max: 150 }),
    body('bmi').isFloat({ min: 5, max: 80 }),
    body('smoker').isIn(['No', 'Yes', 'Ex-smoker']),
    body('activity').isIn(['Active', 'Moderate', 'Sedentary']),
    body('family_history').isIn(['None', 'Diabetes', 'Heart Disease', 'Cancer', 'Hypertension']),
    body('blood_pressure').isIn(['Normal', 'Pre-hypertension', 'Stage 1 HT', 'Stage 2 HT']),
  ],
  validate,
  async (req, res) => {
    try {
      const { patient_id, age, bmi, smoker, activity, family_history, blood_pressure } = req.body;

      // Calculate individual factor scores for transparency
      const { rows: scoreRows } = await query(
        `SELECT calc_risk_score($1,$2,$3,$4,$5,$6) AS score`,
        [age, bmi, smoker, activity, family_history, blood_pressure]
      );
      const score = scoreRows[0].score;

      // Derive per-factor values (mirrors dashboard factor display)
      const ageFactor   = age > 60 ? 25 : age > 45 ? 15 : age > 30 ? 8 : 0;
      const bmiFactor   = bmi > 35 ? 25 : bmi > 30 ? 20 : bmi > 25 ? 10 : 0;
      const smokeFactor = smoker === 'Yes' ? 18 : smoker === 'Ex-smoker' ? 8 : 0;
      const actFactor   = activity === 'Sedentary' ? 12 : activity === 'Moderate' ? 5 : 0;
      const famFactor   = family_history !== 'None' ? 15 : 0;
      const bpFactor    = blood_pressure === 'Stage 2 HT' ? 20
                        : blood_pressure === 'Stage 1 HT' ? 12
                        : blood_pressure === 'Pre-hypertension' ? 6 : 0;

      const { rows: levelRows } = await query(
        `SELECT classify_risk($1) AS level`, [score]
      );
      const level = levelRows[0].level;

      // Persist assessment (triggers auto-alert + patient risk sync)
      const { rows } = await query(
        `INSERT INTO risk_assessment
           (patient_id, risk_score, risk_level,
            age_factor, bmi_factor, smoking_factor,
            activity_factor, family_factor, bp_factor)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9)
         RETURNING *`,
        [patient_id, score, level, ageFactor, bmiFactor, smokeFactor, actFactor, famFactor, bpFactor]
      );

      res.status(201).json({
        success: true,
        data: {
          ...rows[0],
          factors: { ageFactor, bmiFactor, smokeFactor, actFactor, famFactor, bpFactor }
        }
      });
    } catch (err) {
      res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ── GET /risk/assessments  ── full history ───────────────────
router.get('/assessments', async (req, res) => {
  try {
    const { rows } = await query(
      `SELECT ra.*, p.name AS patient_name
       FROM risk_assessment ra
       JOIN patient p ON ra.patient_id = p.patient_id
       ORDER BY ra.assessed_at DESC
       LIMIT 200`
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /risk/high  ── high-risk patient list ────────────────
router.get('/high', async (_req, res) => {
  try {
    const { rows } = await query(`SELECT * FROM vw_high_risk_patients`);
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /risk/assessments/:patientId  ── by patient ──────────
router.get('/assessments/:patientId', async (req, res) => {
  try {
    const { rows } = await query(
      `SELECT * FROM risk_assessment
       WHERE patient_id = $1
       ORDER BY assessed_at DESC`,
      [req.params.patientId]
    );
    res.json({ success: true, data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
