const express = require('express');
const { query } = require('../config/db');
const { authenticate } = require('../middleware/auth');
const asyncHandler = require('../utils/asyncHandler');

const router = express.Router();
router.use(authenticate);

// GET /api/my-member : the authenticated user's own member profile, if one exists.
router.get('/my-member', asyncHandler(async (req, res) => {
  const result = await query(
    'SELECT * FROM public.members WHERE user_id = $1 LIMIT 1',
    [req.user.id]
  );
  res.json({ success: true, data: result.rows[0] || null });
}));

module.exports = router;
