-- ============================================================
--  Disease Risk Prediction & Patient Analytics
--  PostgreSQL Schema — Ready for Neon / Railway / Render
--  Run this ONCE in your database SQL console
-- ============================================================

-- ─── Step 1: Extensions ──────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── Step 2: Drop existing types if re-running ───────────────
DO $$ BEGIN
  DROP TYPE IF EXISTS gender_type   CASCADE;
  DROP TYPE IF EXISTS blood_type    CASCADE;
  DROP TYPE IF EXISTS risk_level    CASCADE;
  DROP TYPE IF EXISTS severity_type CASCADE;
  DROP TYPE IF EXISTS alert_status  CASCADE;
  DROP TYPE IF EXISTS report_type   CASCADE;
EXCEPTION WHEN OTHERS THEN NULL;
END $$;

-- ─── Step 3: ENUMS ───────────────────────────────────────────
CREATE TYPE gender_type    AS ENUM ('Male', 'Female', 'Other');
CREATE TYPE blood_type     AS ENUM ('A+','A-','B+','B-','AB+','AB-','O+','O-');
CREATE TYPE risk_level     AS ENUM ('Low', 'Medium', 'High', 'Critical');
CREATE TYPE severity_type  AS ENUM ('Mild', 'Moderate', 'Severe');
CREATE TYPE alert_status   AS ENUM ('Active', 'Resolved', 'Dismissed');
CREATE TYPE report_type    AS ENUM ('Disease Trend','High Risk','Demographics','Symptom Analysis');

-- ─── Step 4: SEQUENCES ───────────────────────────────────────
CREATE SEQUENCE IF NOT EXISTS seq_patient  START 1001 INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS seq_alert    START 1    INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS seq_report   START 1    INCREMENT 1;
CREATE SEQUENCE IF NOT EXISTS seq_assess   START 1    INCREMENT 1;

-- ─── Step 5: TABLES ──────────────────────────────────────────

CREATE TABLE IF NOT EXISTS doctor (
    doctor_id   SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    specialty   VARCHAR(100),
    email       VARCHAR(150) UNIQUE,
    phone       VARCHAR(20),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS patient (
    patient_id  VARCHAR(12)  PRIMARY KEY DEFAULT ('P' || LPAD(nextval('seq_patient')::TEXT, 4, '0')),
    name        VARCHAR(120) NOT NULL,
    dob         DATE         NOT NULL,
    gender      gender_type  NOT NULL,
    blood_group blood_type,
    phone       VARCHAR(20),
    email       VARCHAR(150),
    address     TEXT,
    doctor_id   INT REFERENCES doctor(doctor_id) ON DELETE SET NULL,
    risk_level  risk_level   NOT NULL DEFAULT 'Low',
    created_at  TIMESTAMPTZ  DEFAULT NOW(),
    updated_at  TIMESTAMPTZ  DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS disease (
    disease_id   SERIAL PRIMARY KEY,
    name         VARCHAR(120) NOT NULL UNIQUE,
    category     VARCHAR(80),
    description  TEXT,
    icd_code     VARCHAR(10)
);

CREATE TABLE IF NOT EXISTS diagnosis (
    diagnosis_id    SERIAL PRIMARY KEY,
    patient_id      VARCHAR(12) NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    disease_id      INT         NOT NULL REFERENCES disease(disease_id),
    diagnosis_date  DATE        NOT NULL DEFAULT CURRENT_DATE,
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS symptom (
    symptom_id   SERIAL PRIMARY KEY,
    symptom_name VARCHAR(100) NOT NULL UNIQUE
);

CREATE TABLE IF NOT EXISTS patient_symptom (
    id            SERIAL PRIMARY KEY,
    patient_id    VARCHAR(12)   NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    symptom_id    INT           NOT NULL REFERENCES symptom(symptom_id),
    severity      severity_type NOT NULL DEFAULT 'Mild',
    reported_date DATE          NOT NULL DEFAULT CURRENT_DATE,
    UNIQUE (patient_id, symptom_id, reported_date)
);

CREATE TABLE IF NOT EXISTS risk_assessment (
    assessment_id   VARCHAR(12)  PRIMARY KEY DEFAULT ('RA' || LPAD(nextval('seq_assess')::TEXT, 4, '0')),
    patient_id      VARCHAR(12)  NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    risk_score      INT          NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_level      risk_level   NOT NULL,
    age_factor      INT          DEFAULT 0,
    bmi_factor      INT          DEFAULT 0,
    smoking_factor  INT          DEFAULT 0,
    activity_factor INT          DEFAULT 0,
    family_factor   INT          DEFAULT 0,
    bp_factor       INT          DEFAULT 0,
    assessed_at     TIMESTAMPTZ  DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS alert (
    alert_id     VARCHAR(12)  PRIMARY KEY DEFAULT ('ALT' || LPAD(nextval('seq_alert')::TEXT, 3, '0')),
    patient_id   VARCHAR(12)  NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    risk_level   risk_level   NOT NULL,
    message      TEXT         NOT NULL,
    status       alert_status NOT NULL DEFAULT 'Active',
    triggered_at TIMESTAMPTZ  DEFAULT NOW(),
    resolved_at  TIMESTAMPTZ
);

CREATE TABLE IF NOT EXISTS report (
    report_id    VARCHAR(12)  PRIMARY KEY DEFAULT ('RPT' || LPAD(nextval('seq_report')::TEXT, 3, '0')),
    report_type  report_type  NOT NULL,
    summary      TEXT,
    generated_at TIMESTAMPTZ  DEFAULT NOW()
);

-- ─── Step 6: FUNCTIONS ───────────────────────────────────────

CREATE OR REPLACE FUNCTION calc_risk_score(
    p_age      INT,
    p_bmi      NUMERIC,
    p_smoker   VARCHAR,
    p_activity VARCHAR,
    p_family   VARCHAR,
    p_bp       VARCHAR
) RETURNS INT LANGUAGE plpgsql AS $$
DECLARE
    v_score INT := 0;
BEGIN
    IF p_age > 60    THEN v_score := v_score + 25;
    ELSIF p_age > 45 THEN v_score := v_score + 15;
    ELSIF p_age > 30 THEN v_score := v_score + 8;
    END IF;

    IF p_bmi > 35    THEN v_score := v_score + 25;
    ELSIF p_bmi > 30 THEN v_score := v_score + 20;
    ELSIF p_bmi > 25 THEN v_score := v_score + 10;
    END IF;

    IF    p_smoker = 'Yes'       THEN v_score := v_score + 18;
    ELSIF p_smoker = 'Ex-smoker' THEN v_score := v_score + 8;
    END IF;

    IF    p_activity = 'Sedentary' THEN v_score := v_score + 12;
    ELSIF p_activity = 'Moderate'  THEN v_score := v_score + 5;
    END IF;

    IF p_family IN ('Diabetes','Heart Disease','Cancer','Hypertension') THEN
        v_score := v_score + 15;
    END IF;

    IF    p_bp = 'Stage 2 HT'       THEN v_score := v_score + 20;
    ELSIF p_bp = 'Stage 1 HT'       THEN v_score := v_score + 12;
    ELSIF p_bp = 'Pre-hypertension' THEN v_score := v_score + 6;
    END IF;

    RETURN LEAST(v_score, 100);
END;
$$;

CREATE OR REPLACE FUNCTION classify_risk(p_score INT)
RETURNS risk_level LANGUAGE plpgsql AS $$
BEGIN
    IF    p_score >= 75 THEN RETURN 'Critical';
    ELSIF p_score >= 50 THEN RETURN 'High';
    ELSIF p_score >= 25 THEN RETURN 'Medium';
    ELSE                     RETURN 'Low';
    END IF;
END;
$$;

-- ─── Step 7: TRIGGERS ────────────────────────────────────────

CREATE OR REPLACE FUNCTION trg_auto_diag_date_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.diagnosis_date IS NULL THEN
        NEW.diagnosis_date := CURRENT_DATE;
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_diag_date ON diagnosis;
CREATE TRIGGER trg_auto_diag_date
BEFORE INSERT ON diagnosis
FOR EACH ROW EXECUTE FUNCTION trg_auto_diag_date_fn();

CREATE OR REPLACE FUNCTION trg_patient_updated_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_patient_updated ON patient;
CREATE TRIGGER trg_patient_updated
BEFORE UPDATE ON patient
FOR EACH ROW EXECUTE FUNCTION trg_patient_updated_fn();

CREATE OR REPLACE FUNCTION trg_auto_alert_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.risk_level IN ('High', 'Critical') THEN
        INSERT INTO alert (patient_id, risk_level, message)
        VALUES (
            NEW.patient_id,
            NEW.risk_level,
            'Auto-alert: Risk score ' || NEW.risk_score || ' (' || NEW.risk_level || ') detected for patient ' || NEW.patient_id
        );
    END IF;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_auto_alert ON risk_assessment;
CREATE TRIGGER trg_auto_alert
AFTER INSERT ON risk_assessment
FOR EACH ROW EXECUTE FUNCTION trg_auto_alert_fn();

CREATE OR REPLACE FUNCTION trg_sync_patient_risk_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE patient
    SET risk_level = NEW.risk_level
    WHERE patient_id = NEW.patient_id;
    RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_sync_patient_risk ON risk_assessment;
CREATE TRIGGER trg_sync_patient_risk
AFTER INSERT ON risk_assessment
FOR EACH ROW EXECUTE FUNCTION trg_sync_patient_risk_fn();

-- ─── Step 8: VIEWS ───────────────────────────────────────────

CREATE OR REPLACE VIEW vw_high_risk_patients AS
SELECT
    p.patient_id,
    p.name,
    p.dob,
    p.gender,
    ra.risk_score,
    ra.risk_level,
    ra.assessed_at
FROM patient p
LEFT JOIN LATERAL (
    SELECT * FROM risk_assessment ra
    WHERE ra.patient_id = p.patient_id
    ORDER BY ra.assessed_at DESC
    LIMIT 1
) ra ON TRUE
WHERE ra.risk_level IN ('High', 'Critical')
ORDER BY ra.risk_score DESC;

CREATE OR REPLACE VIEW vw_patient_symptoms AS
SELECT
    p.name        AS patient_name,
    p.patient_id,
    s.symptom_name,
    ps.severity,
    ps.reported_date,
    ra.risk_level
FROM patient p
JOIN patient_symptom ps ON p.patient_id = ps.patient_id
JOIN symptom          s  ON ps.symptom_id = s.symptom_id
LEFT JOIN LATERAL (
    SELECT risk_level FROM risk_assessment
    WHERE patient_id = p.patient_id
    ORDER BY assessed_at DESC LIMIT 1
) ra ON TRUE
ORDER BY p.name;

CREATE OR REPLACE VIEW vw_disease_by_category AS
SELECT
    d.category,
    COUNT(*)                     AS disease_count,
    COUNT(diag.diagnosis_id)     AS total_diagnoses
FROM disease d
LEFT JOIN diagnosis diag ON d.disease_id = diag.disease_id
GROUP BY d.category
ORDER BY total_diagnoses DESC;

CREATE OR REPLACE VIEW vw_analytics_summary AS
SELECT
    COUNT(DISTINCT p.patient_id)                                                        AS total_patients,
    ROUND(AVG(ra.risk_score))                                                           AS avg_risk_score,
    ROUND(AVG(EXTRACT(YEAR FROM AGE(p.dob))))                                           AS avg_age,
    COUNT(DISTINCT CASE WHEN p.risk_level IN ('High','Critical') THEN p.patient_id END) AS high_risk_count
FROM patient p
LEFT JOIN LATERAL (
    SELECT risk_score FROM risk_assessment
    WHERE patient_id = p.patient_id
    ORDER BY assessed_at DESC LIMIT 1
) ra ON TRUE;

-- ─── Step 9: SEED DATA ───────────────────────────────────────

INSERT INTO doctor (name, specialty, email) VALUES
    ('Dr. Rajan Sharma', 'Cardiology',       'rajan.sharma@hospital.com'),
    ('Dr. Ravi Sharma',  'General Medicine', 'ravi.sharma@hospital.com'),
    ('Dr. Neha Verma',   'Endocrinology',    'neha.verma@hospital.com')
ON CONFLICT (email) DO NOTHING;

INSERT INTO disease (name, category, icd_code) VALUES
    ('Type 2 Diabetes',        'Endocrine',       'E11'),
    ('Hypertension',           'Cardiovascular',  'I10'),
    ('Coronary Artery Disease','Cardiovascular',  'I25'),
    ('COPD',                   'Respiratory',     'J44'),
    ('Asthma',                 'Respiratory',     'J45'),
    ('Obesity',                'Metabolic',       'E66'),
    ('Stroke',                 'Neurological',    'I64'),
    ('Chronic Kidney Disease', 'Renal',           'N18'),
    ('Liver Cirrhosis',        'Hepatic',         'K74'),
    ('Anemia',                 'Hematological',   'D64'),
    ('Arthritis',              'Musculoskeletal', 'M13'),
    ('Depression',             'Mental Health',   'F32')
ON CONFLICT (name) DO NOTHING;

INSERT INTO symptom (symptom_name) VALUES
    ('Fever'), ('Chest Pain'), ('Shortness of Breath'),
    ('Fatigue'), ('Headache'), ('High Blood Pressure'),
    ('Nausea'), ('Joint Pain'), ('Dizziness'),
    ('Weight Loss'), ('Blurred Vision'), ('Frequent Urination')
ON CONFLICT (symptom_name) DO NOTHING;

-- ─── Step 10: Sample patients (optional — delete if not needed) ─
INSERT INTO patient (name, dob, gender, blood_group, phone, email, doctor_id, risk_level) VALUES
    ('Amit Sharma',   '1978-04-12', 'Male',   'B+', '9876543210', 'amit.sharma@email.com',   1, 'High'),
    ('Priya Verma',   '1990-08-25', 'Female', 'A+', '9876543211', 'priya.verma@email.com',   2, 'Medium'),
    ('Rahul Singh',   '1965-11-03', 'Male',   'O+', '9876543212', 'rahul.singh@email.com',   1, 'Critical'),
    ('Sunita Patel',  '1983-02-17', 'Female', 'AB+','9876543213', 'sunita.patel@email.com',  3, 'Low'),
    ('Vikram Kumar',  '1955-07-30', 'Male',   'A-', '9876543214', 'vikram.kumar@email.com',  2, 'High')
ON CONFLICT DO NOTHING;

-- ============================================================
--  Schema setup complete!
--  Tables created: doctor, patient, disease, diagnosis,
--                  symptom, patient_symptom, risk_assessment,
--                  alert, report
--  Functions: calc_risk_score, classify_risk
--  Triggers: auto diagnosis date, patient updated_at,
--            auto alert on high risk, sync patient risk level
--  Views: vw_high_risk_patients, vw_patient_symptoms,
--         vw_disease_by_category, vw_analytics_summary
-- ============================================================
