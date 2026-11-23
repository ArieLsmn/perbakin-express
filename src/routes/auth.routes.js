const express = require('express');
const bcrypt = require('bcryptjs');
const jwt = require('jsonwebtoken');
const { query, pool } = require('../config/db');
const { jwtSecret, jwtExpiresIn } = require('../config/env');
const asyncHandler = require('../utils/asyncHandler');
const httpError = require('../utils/httpError');
const { authenticate } = require('../middleware/auth');

const router = express.Router();

function createToken(user) {
  return jwt.sign({ sub: user.id, email: user.email }, jwtSecret, { expiresIn: jwtExpiresIn });
}

// POST /api/auth/register
router.post('/register', asyncHandler(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  const name = String(req.body.name || '').trim();

  if (!email || !/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw httpError(400, 'A valid email address is required.');
  }
  if (password.length < 8) throw httpError(400, 'Password must be at least 8 characters.');
  if (password.length > 72) throw httpError(400, 'Password must not exceed 72 characters.');
  if (name.length > 150) throw httpError(400, 'Name must not exceed 150 characters.');

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    const exists = await client.query(
      'SELECT 1 FROM auth.users WHERE lower(email) = lower($1) AND deleted_at IS NULL',
      [email]
    );
    if (exists.rowCount) throw httpError(409, 'Email is already registered.');

    const idResult = await client.query('SELECT gen_random_uuid() AS id');
    const id = idResult.rows[0].id;
    const hash = await bcrypt.hash(password, 12);

    const inserted = await client.query(
      `INSERT INTO auth.users
         (id, aud, role, email, encrypted_password, email_confirmed_at,
          raw_user_meta_data, created_at, updated_at, is_sso_user, is_anonymous)
       VALUES ($1, 'authenticated', 'authenticated', $2, $3, now(),
               $4::jsonb, now(), now(), false, false)
       RETURNING id, email, created_at`,
      [id, email, hash, JSON.stringify(name ? { name } : {})]
    );
    await client.query(
      `INSERT INTO public.user_roles (user_id, role) VALUES ($1, 'user')`,
      [id]
    );
    await client.query('COMMIT');

    const user = inserted.rows[0];
    res.status(201).json({
      success: true,
      message: 'Registration successful.',
      data: { user, token: createToken(user) }
    });
  } catch (err) {
    await client.query('ROLLBACK');
    if (err.code === '23505') throw httpError(409, 'Email is already registered.');
    throw err;
  } finally {
    client.release();
  }
}));

// POST /api/auth/login
router.post('/login', asyncHandler(async (req, res) => {
  const email = String(req.body.email || '').trim().toLowerCase();
  const password = String(req.body.password || '');
  if (!email || !password) throw httpError(400, 'Email and password are required.');

  const result = await query(
    `SELECT id, email, encrypted_password
       FROM auth.users
      WHERE lower(email) = lower($1) AND deleted_at IS NULL`,
    [email]
  );
  if (!result.rowCount || !(await bcrypt.compare(password, result.rows[0].encrypted_password || ''))) {
    throw httpError(401, 'Invalid email or password.');
  }

  const user = result.rows[0];
  await query('UPDATE auth.users SET last_sign_in_at = now(), updated_at = now() WHERE id = $1', [user.id]);
  const roleResult = await query(
    `SELECT role::text AS role FROM public.user_roles
      WHERE user_id = $1 ORDER BY CASE WHEN role = 'admin' THEN 0 ELSE 1 END LIMIT 1`,
    [user.id]
  );

  res.json({
    success: true,
    data: {
      user: { id: user.id, email: user.email, role: roleResult.rows[0]?.role || 'user' },
      token: createToken(user)
    }
  });
}));

// GET /api/auth/me
router.get('/me', authenticate, (req, res) => {
  res.json({ success: true, data: { user: req.user } });
});

module.exports = router;
