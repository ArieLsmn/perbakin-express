const express = require('express');
const cors = require('cors');
const helmet = require('helmet');
const rateLimit = require('express-rate-limit');
const { port, corsOrigin, nodeEnv } = require('./config/env');
const { query, pool } = require('./config/db');
const authRoutes = require('./routes/auth.routes');
const resourceRoutes = require('./routes/resource.routes');
const memberRoutes = require('./routes/member.routes');

const app = express();
app.disable('x-powered-by');
app.use(helmet());
app.use(cors({
  origin: corsOrigin === '*' ? '*' : corsOrigin.split(',').map(v => v.trim()),
  credentials: corsOrigin !== '*'
}));
app.use(express.json({ limit: '1mb' }));
app.use(express.urlencoded({ extended: false, limit: '1mb' }));

app.get('/health', async (req, res, next) => {
  try {
    await query('SELECT 1');
    res.json({ success: true, message: 'API and PostgreSQL are reachable.' });
  } catch (err) { next(err); }
});

const authLimiter = rateLimit({
  windowMs: 15 * 60 * 1000,
  limit: 30,
  standardHeaders: 'draft-7',
  legacyHeaders: false,
  message: { success: false, message: 'Too many authentication requests. Try again later.' }
});
app.use('/api/auth', authLimiter, authRoutes);
app.use('/api', memberRoutes);
app.use('/api', resourceRoutes);

app.use((req, res) => {
  res.status(404).json({ success: false, message: 'Endpoint not found.' });
});

app.use((err, req, res, next) => {
  if (nodeEnv !== 'production') console.error(err);
  const status = err.status || (err.code === '23503' ? 400 : err.code === '23505' ? 409 : 500);
  let message = err.message || 'Internal server error.';
  if (status === 500 && nodeEnv === 'production') message = 'Internal server error.';
  res.status(status).json({ success: false, message });
});

const server = app.listen(port, () => {
  console.log(`PERBAKIN API listening on http://localhost:${port}`);
});

async function shutdown() {
  console.log('Shutting down...');
  server.close(async () => {
    await pool.end();
    process.exit(0);
  });
}
process.on('SIGINT', shutdown);
process.on('SIGTERM', shutdown);
