// routes/patients.js
const express = require('express');
const { body, param, query: qv, validationResult } = require('express-validator');
const { query } = require('../db/pool');

const router = express.Router();

// ── Validation middleware ─────────────────────────────────────
const validate = (req, res, next) => {
  const errors = validationResult(req);
  if (!errors.isEmpty())
    return res.status(400).json({ success: false, errors: errors.array() });
  next();
};

// ── GET /patients  ── list / search ──────────────────────────
router.get('/', async (req, res) => {
  try {
    const { search = '', limit = 100, offset = 0 } = req.query;
    const like = `%${search}%`;

    const { rows } = await query(
      `SELECT
         p.patient_id, p.name, p.dob, p.gender, p.blood_group,
         p.phone, p.email, p.risk_level,
         d.name AS doctor_name,
         p.created_at,
         EXTRACT(YEAR FROM AGE(p.dob))::INT AS age,
         ARRAY(
           SELECT s.symptom_name
           FROM patient_symptom ps
           JOIN symptom s ON ps.symptom_id = s.symptom_id
           WHERE ps.patient_id = p.patient_id
           ORDER BY ps.reported_date DESC
           LIMIT 5
         ) AS symptoms
       FROM patient p
       LEFT JOIN doctor d ON p.doctor_id = d.doctor_id
       WHERE p.name      ILIKE $1
          OR p.patient_id ILIKE $1
          OR p.email      ILIKE $1
       ORDER BY p.created_at DESC
       LIMIT $2 OFFSET $3`,
      [like, limit, offset]
    );

    const count = await query(
      `SELECT COUNT(*) FROM patient WHERE name ILIKE $1 OR patient_id ILIKE $1`,
      [like]
    );

    res.json({ success: true, total: Number(count.rows[0].count), data: rows });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── GET /patients/:id  ── single patient ─────────────────────
router.get('/:id', async (req, res) => {
  try {
    const { rows } = await query(
      `SELECT
         p.*,
         EXTRACT(YEAR FROM AGE(p.dob))::INT AS age,
         d.name AS doctor_name,
         (
           SELECT row_to_json(ra)
           FROM risk_assessment ra
           WHERE ra.patient_id = p.patient_id
           ORDER BY ra.assessed_at DESC LIMIT 1
         ) AS latest_assessment
       FROM patient p
       LEFT JOIN doctor d ON p.doctor_id = d.doctor_id
       WHERE p.patient_id = $1`,
      [req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, message: 'Patient not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── POST /patients  ── register ───────────────────────────────
router.post(
  '/',
  [
    body('name').trim().notEmpty().withMessage('Name is required'),
    body('dob').isDate().withMessage('Valid DOB required'),
    body('gender').isIn(['Male', 'Female', 'Other']).withMessage('Invalid gender'),
    body('blood_group').optional().isIn(['A+','A-','B+','B-','AB+','AB-','O+','O-']),
    body('phone').optional().trim(),
    body('email').optional().isEmail().normalizeEmail(),
    body('doctor_id').optional().isInt(),
  ],
  validate,
  async (req, res) => {
    try {
      const { name, dob, gender, blood_group, phone, email, address, doctor_id } = req.body;
      const { rows } = await query(
        `INSERT INTO patient (name, dob, gender, blood_group, phone, email, address, doctor_id)
         VALUES ($1,$2,$3,$4,$5,$6,$7,$8)
         RETURNING *`,
        [name, dob, gender, blood_group || null, phone || null, email || null, address || null, doctor_id || null]
      );
      res.status(201).json({ success: true, data: rows[0] });
    } catch (err) {
      res.status(500).json({ success: false, message: err.message });
    }
  }
);

// ── PUT /patients/:id  ── update ─────────────────────────────
router.put('/:id', async (req, res) => {
  try {
    const { name, dob, gender, blood_group, phone, email, address, doctor_id } = req.body;
    const { rows } = await query(
      `UPDATE patient SET
         name=$1, dob=$2, gender=$3, blood_group=$4,
         phone=$5, email=$6, address=$7, doctor_id=$8
       WHERE patient_id=$9 RETURNING *`,
      [name, dob, gender, blood_group || null, phone || null, email || null, address || null, doctor_id || null, req.params.id]
    );
    if (!rows.length) return res.status(404).json({ success: false, message: 'Patient not found' });
    res.json({ success: true, data: rows[0] });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

// ── DELETE /patients/:id ──────────────────────────────────────
router.delete('/:id', async (req, res) => {
  try {
    const { rowCount } = await query(
      `DELETE FROM patient WHERE patient_id=$1`,
      [req.params.id]
    );
    if (!rowCount) return res.status(404).json({ success: false, message: 'Patient not found' });
    res.json({ success: true, message: 'Patient deleted' });
  } catch (err) {
    res.status(500).json({ success: false, message: err.message });
  }
});

module.exports = router;
