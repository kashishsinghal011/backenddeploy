-- ============================================================
--  Disease Risk Prediction & Patient Analytics  — DB Schema
--  PostgreSQL (matches Oracle PL/SQL shown in the SQL console)
-- ============================================================

-- ─── Extensions ──────────────────────────────────────────────
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- ─── ENUMS ───────────────────────────────────────────────────
CREATE TYPE gender_type    AS ENUM ('Male', 'Female', 'Other');
CREATE TYPE blood_type     AS ENUM ('A+','A-','B+','B-','AB+','AB-','O+','O-');
CREATE TYPE risk_level     AS ENUM ('Low', 'Medium', 'High', 'Critical');
CREATE TYPE severity_type  AS ENUM ('Mild', 'Moderate', 'Severe');
CREATE TYPE alert_status   AS ENUM ('Active', 'Resolved', 'Dismissed');
CREATE TYPE report_type    AS ENUM ('Disease Trend','High Risk','Demographics','Symptom Analysis');

-- ─── SEQUENCE (mimics Oracle SEQ_PATIENT) ────────────────────
CREATE SEQUENCE seq_patient  START 1001 INCREMENT 1;
CREATE SEQUENCE seq_alert    START 1    INCREMENT 1;
CREATE SEQUENCE seq_report   START 1    INCREMENT 1;
CREATE SEQUENCE seq_assess   START 1    INCREMENT 1;

-- ─── DOCTOR ──────────────────────────────────────────────────
CREATE TABLE doctor (
    doctor_id   SERIAL PRIMARY KEY,
    name        VARCHAR(100) NOT NULL,
    specialty   VARCHAR(100),
    email       VARCHAR(150) UNIQUE,
    phone       VARCHAR(20),
    created_at  TIMESTAMPTZ DEFAULT NOW()
);

-- ─── PATIENT ─────────────────────────────────────────────────
CREATE TABLE patient (
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

-- ─── DISEASE ─────────────────────────────────────────────────
CREATE TABLE disease (
    disease_id   SERIAL PRIMARY KEY,
    name         VARCHAR(120) NOT NULL UNIQUE,
    category     VARCHAR(80),
    description  TEXT,
    icd_code     VARCHAR(10)
);

-- ─── DIAGNOSIS ───────────────────────────────────────────────
CREATE TABLE diagnosis (
    diagnosis_id    SERIAL PRIMARY KEY,
    patient_id      VARCHAR(12) NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    disease_id      INT         NOT NULL REFERENCES disease(disease_id),
    diagnosis_date  DATE        NOT NULL DEFAULT CURRENT_DATE,   -- mirrors trg_auto_diag_date trigger
    notes           TEXT,
    created_at      TIMESTAMPTZ DEFAULT NOW()
);

-- ─── SYMPTOM ─────────────────────────────────────────────────
CREATE TABLE symptom (
    symptom_id   SERIAL PRIMARY KEY,
    symptom_name VARCHAR(100) NOT NULL UNIQUE
);

-- ─── PATIENT_SYMPTOM ─────────────────────────────────────────
CREATE TABLE patient_symptom (
    id            SERIAL PRIMARY KEY,
    patient_id    VARCHAR(12)   NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    symptom_id    INT           NOT NULL REFERENCES symptom(symptom_id),
    severity      severity_type NOT NULL DEFAULT 'Mild',
    reported_date DATE          NOT NULL DEFAULT CURRENT_DATE,
    UNIQUE (patient_id, symptom_id, reported_date)
);

-- ─── RISK_ASSESSMENT ─────────────────────────────────────────
CREATE TABLE risk_assessment (
    assessment_id  VARCHAR(12)  PRIMARY KEY DEFAULT ('RA' || LPAD(nextval('seq_assess')::TEXT, 4, '0')),
    patient_id     VARCHAR(12)  NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    risk_score     INT          NOT NULL CHECK (risk_score BETWEEN 0 AND 100),
    risk_level     risk_level   NOT NULL,
    age_factor     INT          DEFAULT 0,
    bmi_factor     INT          DEFAULT 0,
    smoking_factor INT          DEFAULT 0,
    activity_factor INT         DEFAULT 0,
    family_factor  INT          DEFAULT 0,
    bp_factor      INT          DEFAULT 0,
    assessed_at    TIMESTAMPTZ  DEFAULT NOW()
);

-- ─── ALERTS ──────────────────────────────────────────────────
CREATE TABLE alert (
    alert_id    VARCHAR(12)  PRIMARY KEY DEFAULT ('ALT' || LPAD(nextval('seq_alert')::TEXT, 3, '0')),
    patient_id  VARCHAR(12)  NOT NULL REFERENCES patient(patient_id) ON DELETE CASCADE,
    risk_level  risk_level   NOT NULL,
    message     TEXT         NOT NULL,
    status      alert_status NOT NULL DEFAULT 'Active',
    triggered_at TIMESTAMPTZ DEFAULT NOW(),
    resolved_at  TIMESTAMPTZ
);

-- ─── REPORT ──────────────────────────────────────────────────
CREATE TABLE report (
    report_id   VARCHAR(12)  PRIMARY KEY DEFAULT ('RPT' || LPAD(nextval('seq_report')::TEXT, 3, '0')),
    report_type report_type  NOT NULL,
    summary     TEXT,
    generated_at TIMESTAMPTZ DEFAULT NOW()
);

-- ============================================================
--  FUNCTIONS  (mirrors PL/SQL calc_risk_score function)
-- ============================================================
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
    -- Age factor
    IF p_age > 60    THEN v_score := v_score + 25;
    ELSIF p_age > 45 THEN v_score := v_score + 15;
    ELSIF p_age > 30 THEN v_score := v_score + 8;
    END IF;

    -- BMI factor
    IF p_bmi > 35    THEN v_score := v_score + 25;
    ELSIF p_bmi > 30 THEN v_score := v_score + 20;
    ELSIF p_bmi > 25 THEN v_score := v_score + 10;
    END IF;

    -- Smoking factor
    IF    p_smoker = 'Yes'       THEN v_score := v_score + 18;
    ELSIF p_smoker = 'Ex-smoker' THEN v_score := v_score + 8;
    END IF;

    -- Physical activity factor
    IF    p_activity = 'Sedentary' THEN v_score := v_score + 12;
    ELSIF p_activity = 'Moderate'  THEN v_score := v_score + 5;
    END IF;

    -- Family history factor
    IF p_family IN ('Diabetes','Heart Disease','Cancer','Hypertension') THEN
        v_score := v_score + 15;
    END IF;

    -- Blood pressure factor
    IF    p_bp = 'Stage 2 HT'       THEN v_score := v_score + 20;
    ELSIF p_bp = 'Stage 1 HT'       THEN v_score := v_score + 12;
    ELSIF p_bp = 'Pre-hypertension' THEN v_score := v_score + 6;
    END IF;

    RETURN LEAST(v_score, 100);
END;
$$;

-- ─── FUNCTION: classify risk level from score ─────────────────
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

-- ============================================================
--  TRIGGERS  (mirrors Oracle trg_auto_diag_date)
-- ============================================================

-- Auto-set diagnosis_date if NULL (diagnosis table)
CREATE OR REPLACE FUNCTION trg_auto_diag_date_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    IF NEW.diagnosis_date IS NULL THEN
        NEW.diagnosis_date := CURRENT_DATE;
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_auto_diag_date
BEFORE INSERT ON diagnosis
FOR EACH ROW EXECUTE FUNCTION trg_auto_diag_date_fn();

-- Auto-update patient.updated_at
CREATE OR REPLACE FUNCTION trg_patient_updated_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    NEW.updated_at := NOW();
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_patient_updated
BEFORE UPDATE ON patient
FOR EACH ROW EXECUTE FUNCTION trg_patient_updated_fn();

-- Auto-create alert when risk assessment is High/Critical
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

CREATE TRIGGER trg_auto_alert
AFTER INSERT ON risk_assessment
FOR EACH ROW EXECUTE FUNCTION trg_auto_alert_fn();

-- Auto-update patient.risk_level after new risk_assessment
CREATE OR REPLACE FUNCTION trg_sync_patient_risk_fn()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
    UPDATE patient
    SET risk_level = NEW.risk_level
    WHERE patient_id = NEW.patient_id;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_sync_patient_risk
AFTER INSERT ON risk_assessment
FOR EACH ROW EXECUTE FUNCTION trg_sync_patient_risk_fn();

-- ============================================================
--  VIEWS (mirrors dashboard SQL queries)
-- ============================================================

-- High-risk patients view
CREATE VIEW vw_high_risk_patients AS
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

-- Patient symptom join view
CREATE VIEW vw_patient_symptoms AS
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

-- Disease count by category
CREATE VIEW vw_disease_by_category AS
SELECT
    d.category,
    COUNT(*)         AS disease_count,
    COUNT(diag.diagnosis_id) AS total_diagnoses
FROM disease d
LEFT JOIN diagnosis diag ON d.disease_id = diag.disease_id
GROUP BY d.category
ORDER BY total_diagnoses DESC;

-- Analytics summary
CREATE VIEW vw_analytics_summary AS
SELECT
    COUNT(DISTINCT p.patient_id)                                       AS total_patients,
    ROUND(AVG(ra.risk_score))                                          AS avg_risk_score,
    ROUND(AVG(EXTRACT(YEAR FROM AGE(p.dob))))                         AS avg_age,
    COUNT(DISTINCT CASE WHEN p.risk_level IN ('High','Critical') THEN p.patient_id END) AS high_risk_count
FROM patient p
LEFT JOIN LATERAL (
    SELECT risk_score FROM risk_assessment
    WHERE patient_id = p.patient_id
    ORDER BY assessed_at DESC LIMIT 1
) ra ON TRUE;

-- ============================================================
--  SEED DATA
-- ============================================================

INSERT INTO doctor (name, specialty, email) VALUES
    ('Dr. Rajan Sharma',  'Cardiology',         'rajan.sharma@hospital.com'),
    ('Dr. Ravi Sharma',   'General Medicine',   'ravi.sharma@hospital.com'),
    ('Dr. Neha Verma',    'Endocrinology',      'neha.verma@hospital.com');

INSERT INTO disease (name, category, icd_code) VALUES
    ('Type 2 Diabetes',      'Endocrine',       'E11'),
    ('Hypertension',         'Cardiovascular',  'I10'),
    ('Coronary Artery Disease','Cardiovascular','I25'),
    ('COPD',                 'Respiratory',     'J44'),
    ('Asthma',               'Respiratory',     'J45'),
    ('Obesity',              'Metabolic',       'E66'),
    ('Stroke',               'Neurological',    'I64'),
    ('Chronic Kidney Disease','Renal',          'N18'),
    ('Liver Cirrhosis',      'Hepatic',         'K74'),
    ('Anemia',               'Hematological',   'D64'),
    ('Arthritis',            'Musculoskeletal', 'M13'),
    ('Depression',           'Mental Health',   'F32');

INSERT INTO symptom (symptom_name) VALUES
    ('Fever'), ('Chest Pain'), ('Shortness of Breath'),
    ('Fatigue'), ('Headache'), ('High Blood Pressure'),
    ('Nausea'), ('Joint Pain'), ('Dizziness'),
    ('Weight Loss'), ('Blurred Vision'), ('Frequent Urination');
