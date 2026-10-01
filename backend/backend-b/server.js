const express = require('express');

const app = express();
const PORT = 3002;
const HOST = '0.0.0.0';

// Response header to identify Backend B on all responses
app.use((req, res, next) => {
  res.set('X-Backend', 'B');
  next();
});

// GET / - Baseline application response identifying Backend B
app.get('/', (req, res) => {
  res.json({
    backend: 'B',
    status: 'ok',
    message: 'Backend B is running'
  });
});

// GET /api/status - Health / status information with caching headers
app.get('/api/status', (req, res) => {
  res.set('Cache-Control', 'public, max-age=60');
  res.json({
    backend: 'B',
    status: 'ok'
  });
});

// 404 handler for unknown routes
app.use((req, res) => {
  res.status(404).json({
    error: 'Not Found'
  });
});

app.listen(PORT, HOST, () => {
  console.log(`Backend B running on http://${HOST}:${PORT}`);
});
