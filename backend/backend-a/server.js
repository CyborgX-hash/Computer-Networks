const express = require('express');

const app = express();
const PORT = 3001;
const HOST = '0.0.0.0';

// Response header to identify Backend A on all responses
app.use((req, res, next) => {
  res.set('X-Backend', 'A');
  next();
});

// GET / - Baseline application response identifying Backend A
app.get('/', (req, res) => {
  res.json({
    backend: 'A',
    status: 'ok',
    message: 'Backend A is running'
  });
});

// GET /api/status - Health / status information with caching headers
app.get('/api/status', (req, res) => {
  res.set('Cache-Control', 'public, max-age=60');
  res.json({
    backend: 'A',
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
  console.log(`Backend A running on http://${HOST}:${PORT}`);
});
