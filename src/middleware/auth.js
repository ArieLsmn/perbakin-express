const jwt = require('jsonwebtoken');
const { query } = require('../config/db');
const { jwtSecret } = require('../config/env');
const asyncHandler = require('../utils/asyncHandler');
const httpError = require('../utils/httpError');

const authenticate = asyncHandler(async (req, res, next) => {
  const header = req.headers.authorization || '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) throw httpError(401, 'Bearer token is required.');

  let payload;
  try {
    payload = jwt.verify(token, jwtSecret);
  } catch {
    throw httpError(401, 'Invalid or expired token.');
  }

  const result = await query(
    `SELECT u.id, u.email, COALESCE(r.role::text, 'user') AS role
       FROM auth.users u
       LEFT JOIN public.user_roles r ON r.user_id = u.id
      WHERE u.id = $1 AND u.deleted_at IS NULL
      ORDER BY CASE WHEN r.role = 'admin' THEN 0 ELSE 1 END
      LIMIT 1`,
    [payload.sub]
  );
  if (!result.rowCount) throw httpError(401, 'User account not found.');
  req.user = result.rows[0];
  next();
});

function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') {
    return res.status(403).json({ success: false, message: 'Administrator access required.' });
  }
  next();
}

module.exports = { authenticate, requireAdmin };
