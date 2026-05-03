# 🏥 Disease Risk Prediction & Patient Analytics — Backend

Node.js + Express REST API backed by **PostgreSQL**.  
Mirrors the Oracle PL/SQL schema shown in the dashboard's SQL Console.

---

## Project Structure

```
disease-risk-backend/
├── server.js              # Express app entry point
├── package.json
├── .env.example           # Copy → .env and fill in your creds
├── db/
│   ├── pool.js            # pg connection pool + auto-init
│   └── schema.sql         # Full schema: tables, functions, triggers, views, seed data
└── routes/
    ├── patients.js        # CRUD for patients
    ├── symptoms.js        # Symptom logging & frequency
    ├── risk.js            # Risk assessment (calls calc_risk_score DB function)
    ├── alerts.js          # Alert management
    ├── analytics.js       # Analytics queries + report generation
    └── lookup.js          # Reference data (doctors, diseases, symptoms)
```

---

## Quick Start (Local)

### 1. Prerequisites
- Node.js ≥ 18
- PostgreSQL ≥ 14

### 2. Create the database
```bash
psql -U postgres -c "CREATE DATABASE disease_risk_db;"
```

### 3. Install & configure
```bash
cp .env.example .env
# Edit .env with your DB credentials
npm install
```

### 4. Run
```bash
npm start        # production
npm run dev      # with nodemon (auto-reload)
```

The server auto-applies `db/schema.sql` on first boot (idempotent check).

---

## API Reference

| Method | Endpoint | Description |
|--------|----------|-------------|
| GET | `/health` | Health check |
| **Patients** | | |
| GET | `/api/patients` | List / search (`?search=&limit=&offset=`) |
| POST | `/api/patients` | Register patient |
| GET | `/api/patients/:id` | Single patient with latest assessment |
| PUT | `/api/patients/:id` | Update patient |
| DELETE | `/api/patients/:id` | Delete patient |
| **Symptoms** | | |
| GET | `/api/symptoms` | Master symptom list |
| GET | `/api/symptoms/patient/:patientId` | Patient's logged symptoms |
| POST | `/api/symptoms/log` | Log symptoms for a patient |
| GET | `/api/symptoms/frequency` | Top symptoms across all patients |
| **Risk** | | |
| POST | `/api/risk/assess` | Calculate + save risk score |
| GET | `/api/risk/assessments` | All risk assessments |
| GET | `/api/risk/high` | High/Critical risk patients |
| GET | `/api/risk/assessments/:patientId` | Risk history for one patient |
| **Alerts** | | |
| GET | `/api/alerts` | Active alerts (auto-created by trigger) |
| GET | `/api/alerts/count` | Active alert count |
| PATCH | `/api/alerts/:id/resolve` | Resolve an alert |
| DELETE | `/api/alerts/:id` | Dismiss alert |
| **Analytics** | | |
| GET | `/api/analytics/summary` | Dashboard KPIs |
| GET | `/api/analytics/risk-breakdown` | Count by risk level |
| GET | `/api/analytics/age-groups` | Patient age distribution |
| GET | `/api/analytics/symptom-frequency` | Top symptoms |
| GET | `/api/analytics/monthly-trends` | Last 6 months patient trends |
| GET | `/api/analytics/reports` | All generated reports |
| POST | `/api/analytics/reports` | Generate a report |
| **Lookup** | | |
| GET | `/api/lookup/doctors` | Doctor list |
| GET | `/api/lookup/diseases` | Disease catalogue |
| GET | `/api/lookup/symptoms` | Symptom master list |

### POST /api/patients — Body
```json
{
  "name": "Priya Sharma",
  "dob": "1980-04-15",
  "gender": "Female",
  "blood_group": "B+",
  "phone": "9876543210",
  "email": "priya@example.com",
  "doctor_id": 1
}
```

### POST /api/risk/assess — Body
```json
{
  "patient_id": "P1001",
  "age": 52,
  "bmi": 29.4,
  "smoker": "Ex-smoker",
  "activity": "Moderate",
  "family_history": "Diabetes",
  "blood_pressure": "Stage 1 HT"
}
```

### POST /api/symptoms/log — Body
```json
{
  "patient_id": "P1001",
  "symptoms": ["Fever", "Fatigue", "Headache"],
  "severity": "Moderate",
  "reported_date": "2026-05-03"
}
```

---

## Deployment

### Railway / Render / Fly.io

1. Push to GitHub.
2. Connect repo in the platform dashboard.
3. Add environment variables from `.env.example`.
4. Set `DB_SSL=true` if the platform requires it (Railway does by default).
5. Use the platform's managed PostgreSQL add-on — copy the `DATABASE_URL` into env vars.

### Docker (optional)

```dockerfile
FROM node:20-alpine
WORKDIR /app
COPY package*.json ./
RUN npm ci --omit=dev
COPY . .
EXPOSE 3001
CMD ["node", "server.js"]
```

```bash
docker build -t disease-risk-api .
docker run -p 3001:3001 --env-file .env disease-risk-api
```

---

## Database Highlights

### PostgreSQL functions (mirrors Oracle PL/SQL)
- **`calc_risk_score(age, bmi, smoker, activity, family, bp)`** → returns INT 0-100
- **`classify_risk(score)`** → returns `risk_level` enum

### Triggers
| Trigger | Table | Action |
|---------|-------|--------|
| `trg_auto_diag_date` | diagnosis | Sets `diagnosis_date` to today if NULL |
| `trg_patient_updated` | patient | Updates `updated_at` on every UPDATE |
| `trg_auto_alert` | risk_assessment | Auto-inserts alert for High/Critical scores |
| `trg_sync_patient_risk` | risk_assessment | Syncs `patient.risk_level` after new assessment |

### Views
- `vw_high_risk_patients` — latest assessment per patient, filtered to High/Critical
- `vw_patient_symptoms` — patient × symptom × risk level JOIN
- `vw_disease_by_category` — GROUP BY disease category with counts
- `vw_analytics_summary` — single-row KPI dashboard

---

## Connecting the Frontend

In your `disease-risk-dashboard.html`, replace the in-memory `DB` object calls with `fetch()` calls to this API.

Example — loading patients:
```javascript
const API = 'http://localhost:3001/api';

async function loadPatients() {
  const res  = await fetch(`${API}/patients`);
  const json = await res.json();
  DB.patients = json.data;
  renderPatientTable();
}
```
