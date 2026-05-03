// db/pool.js — PostgreSQL connection pool
const { Pool } = require('pg');
const fs       = require('fs');
const path     = require('path');
require('dotenv').config();

const useSSL = process.env.DB_SSL === 'true';

const pool = new Pool(
  process.env.DATABASE_URL
    ? {
        connectionString: process.env.DATABASE_URL,
        ssl: useSSL ? { rejectUnauthorized: false } : false,
      }
    : {
        host:     process.env.DB_HOST     || 'localhost',
        port:     Number(process.env.DB_PORT) || 5432,
        database: process.env.DB_NAME     || 'disease_risk_db',
        user:     process.env.DB_USER     || 'postgres',
        password: process.env.DB_PASSWORD || '',
        ssl:      useSSL ? { rejectUnauthorized: false } : false,
      }
);

pool.on('error', (err) => {
  console.error('Unexpected pool error', err.message);
});

// ── Helper: run a query and return rows ──────────────────────
const query = (text, params) => pool.query(text, params);

// ── Helper: get a client for transactions ────────────────────
const getClient = () => pool.connect();

// ── Init: run schema.sql if tables don't exist ───────────────
async function initDB() {
  const sql = fs.readFileSync(path.join(__dirname, 'schema.sql'), 'utf8');
  const client = await pool.connect();
  try {
    // Check if patient table exists already
    const { rows } = await client.query(
      `SELECT to_regclass('public.patient') AS tbl`
    );
    if (rows[0].tbl) {
      console.log('✅  Database already initialised — skipping schema run.');
      return;
    }
    console.log('🔧  Running schema.sql …');
    await client.query(sql);
    console.log('✅  Schema + seed data applied.');
  } catch (err) {
    console.error('❌  DB init error:', err.message);
    throw err;
  } finally {
    client.release();
  }
}

module.exports = { pool, query, getClient, initDB };
