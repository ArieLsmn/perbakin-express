const express = require('express');
const { query, pool } = require('../config/db');
const { authenticate, requireAdmin } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');
const httpError = require('../utils/httpError');

const router = express.Router();

// Explicit allowlist. Never accept a table name directly from arbitrary input.
const TABLES = new Set([
  'members', 'payment', 'senjata', 'document_review', 'user_roles', 'event',
  'izin', 'content', 'member_review', 'memberform', 'member_sponsor',
  'sponsor_form', 'izin_submission_review', 'media_file', 'ipaymu_test_payments',
  'registration_qris_payments', 'member_statistics', 'event_history', 'klub',
  'site_content'
]);
const IDENTIFIER = /^[a-z_][a-z0-9_]*$/;

function tableName(req) {
  const table = req.params.table;
  if (!TABLES.has(table)) throw httpError(404, 'Unknown resource.');
  return `"public"."${table}"`;
}
function validateId(value, table) {
  const isUuidOrInteger = /^[0-9a-f-]{36}$/i.test(value) || /^\d+$/.test(value);
  const isPaymentKey = (table === 'ipaymu_test_payments' && /^PRBK-TEST-[a-f0-9-]{36}$/i.test(value))
    || (table === 'registration_qris_payments' && /^PRBK-REG-[a-f0-9-]{36}$/i.test(value));
  if (!isUuidOrInteger && !isPaymentKey) throw httpError(400, 'Invalid record ID.');
}
async function getColumns(table) {
  const result = await query(
    `SELECT column_name, is_identity, is_generated, column_default
       FROM information_schema.columns
      WHERE table_schema = 'public' AND table_name = $1
      ORDER BY ordinal_position`,
    [table]
  );
  return result.rows;
}
function cleanBody(body, columns, mode = 'insert') {
  if (!body || typeof body !== 'object' || Array.isArray(body)) throw httpError(400, 'JSON object body is required.');
  const allowed = new Set(columns
    .filter(c => c.is_identity !== 'YES' && c.is_generated !== 'ALWAYS')
    .map(c => c.column_name));
  const entries = Object.entries(body).filter(([key]) => {
    if (!IDENTIFIER.test(key) || !allowed.has(key)) throw httpError(400, `Unknown or non-writable column: ${key}`);
    return true;
  });
  if (!entries.length) throw httpError(400, 'At least one writable field is required.');
  if (mode === 'insert') {
    for (const [key] of entries) {
      if (['id', 'created_at', 'date_created', 'updated_at'].includes(key)) {
        // Explicit values are allowed for migration/admin workflows; server defaults apply when omitted.
      }
    }
  }
  return entries;
}

// All resource routes require a valid JWT. Reads are available to authenticated users;
// mutations are administrator-only. Authentication tables are deliberately not exposed here.
router.use(authenticate);

// GET /api/:table
router.get('/:table', asyncHandler(async (req, res) => {
  const table = tableName(req);
  const limit = Math.min(Math.max(Number.parseInt(req.query.limit, 10) || 50, 1), 200);
  const offset = Math.max(Number.parseInt(req.query.offset, 10) || 0, 0);
  const orderBy = String(req.query.orderBy || 'created_at');
  const direction = String(req.query.direction || 'desc').toLowerCase() === 'asc' ? 'ASC' : 'DESC';
  const cols = await getColumns(req.params.table);
  const columnSet = new Set(cols.map(c => c.column_name));
  if (!columnSet.has(orderBy)) throw httpError(400, 'Invalid orderBy column.');

  const result = await query(
    `SELECT * FROM ${table} ORDER BY "${orderBy}" ${direction} LIMIT $1 OFFSET $2`,
    [limit, offset]
  );
  res.json({ success: true, data: result.rows, pagination: { limit, offset, count: result.rowCount } });
}));

// GET /api/:table/:id
router.get('/:table/:id', asyncHandler(async (req, res) => {
  const table = tableName(req);
  validateId(req.params.id, req.params.table);
  const cols = await getColumns(req.params.table);
  const pk = cols.some(c => c.column_name === 'id') ? 'id'
    : req.params.table === 'ipaymu_test_payments' ? 'reference_id'
    : req.params.table === 'registration_qris_payments' ? 'order_id'
    : null;
  if (!pk) throw httpError(400, 'This resource does not have a supported single-column identifier.');
  const result = await query(`SELECT * FROM ${table} WHERE "${pk}" = $1 LIMIT 1`, [req.params.id]);
  if (!result.rowCount) throw httpError(404, 'Record not found.');
  res.json({ success: true, data: result.rows[0] });
}));

// POST /api/:table
router.post('/:table', requireAdmin, asyncHandler(async (req, res) => {
  const table = tableName(req);
  const cols = await getColumns(req.params.table);
  const entries = cleanBody(req.body, cols);
  const names = entries.map(([key]) => `"${key}"`).join(', ');
  const placeholders = entries.map((_, i) => `$${i + 1}`).join(', ');
  const values = entries.map(([, value]) => value);
  const result = await query(
    `INSERT INTO ${table} (${names}) VALUES (${placeholders}) RETURNING *`,
    values
  );
  res.status(201).json({ success: true, data: result.rows[0] });
}));

// PATCH /api/:table/:id
router.patch('/:table/:id', requireAdmin, asyncHandler(async (req, res) => {
  const table = tableName(req);
  validateId(req.params.id, req.params.table);
  const cols = await getColumns(req.params.table);
  const pk = cols.some(c => c.column_name === 'id') ? 'id'
    : req.params.table === 'ipaymu_test_payments' ? 'reference_id'
    : req.params.table === 'registration_qris_payments' ? 'order_id'
    : null;
  if (!pk) throw httpError(400, 'This resource does not have a supported single-column identifier.');
  const entries = cleanBody(req.body, cols, 'update').filter(([key]) => key !== pk);
  if (!entries.length) throw httpError(400, 'No updatable fields supplied.');
  const assignments = entries.map(([key], i) => `"${key}" = $${i + 1}`).join(', ');
  const values = entries.map(([, value]) => value);
  values.push(req.params.id);
  const result = await query(
    `UPDATE ${table} SET ${assignments} WHERE "${pk}" = $${values.length} RETURNING *`,
    values
  );
  if (!result.rowCount) throw httpError(404, 'Record not found.');
  res.json({ success: true, data: result.rows[0] });
}));

// DELETE /api/:table/:id
router.delete('/:table/:id', requireAdmin, asyncHandler(async (req, res) => {
  const table = tableName(req);
  validateId(req.params.id, req.params.table);
  const cols = await getColumns(req.params.table);
  const pk = cols.some(c => c.column_name === 'id') ? 'id'
    : req.params.table === 'ipaymu_test_payments' ? 'reference_id'
    : req.params.table === 'registration_qris_payments' ? 'order_id'
    : null;
  if (!pk) throw httpError(400, 'This resource does not have a supported single-column identifier.');
  const result = await query(`DELETE FROM ${table} WHERE "${pk}" = $1 RETURNING *`, [req.params.id]);
  if (!result.rowCount) throw httpError(404, 'Record not found.');
  res.json({ success: true, message: 'Record deleted.', data: result.rows[0] });
}));

module.exports = router;
