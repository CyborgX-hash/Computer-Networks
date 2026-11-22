const express = require('express');

const app = express();
const PORT = 3001;
const HOST = '0.0.0.0';

// Authorized edge IP whitelist (Requirement C)
// Only Mac 1 (Standby Edge), Mac 2 (Primary Edge), and local host are authorized
const ALLOWED_IPS = new Set([
  '127.0.0.1',
  '::1',
  '::ffff:127.0.0.1',
  '10.200.251.106',          // Mac 1 (Mihika - Standby Edge)
  '::ffff:10.200.251.106',
  '10.200.251.227',          // Mac 2 (Priyanshu - Primary Edge)
  '::ffff:10.200.251.227',
  '10.200.251.76',           // Mac 3 (Self)
  '::ffff:10.200.251.76'
]);

// IP Whitelist Access Control Middleware
app.use((req, res, next) => {
  const clientIp = req.socket.remoteAddress;
  if (!ALLOWED_IPS.has(clientIp)) {
    console.warn(`[SECURITY ALERT] Unauthorized access denied from IP: ${clientIp} to Backend A`);
    return res.status(403).json({
      error: 'Forbidden',
      message: 'Access denied: client IP is not an authorized edge node',
      clientIp: clientIp,
      backend: 'A'
    });
  }
  next();
});

// Response header to identify Backend A on all responses (Preserved from Phase 1)
app.use((req, res, next) => {
  res.set('X-Backend', 'A');
  next();
});

// GET / - Baseline application response identifying Backend A (Preserved from Phase 1)
app.get('/', (req, res) => {
  res.json({
    backend: 'A',
    status: 'ok',
    message: 'Backend A is running'
  });
});

// GET /api/status - Health / status information with caching headers (Preserved from Phase 1)
app.get('/api/status', (req, res) => {
  res.set('Cache-Control', 'public, max-age=60');
  res.json({
    backend: 'A',
    status: 'ok'
  });
});

// GET /health - Phase 2 Dedicated Health Check endpoint
app.get('/health', (req, res) => {
  res.json({
    status: 'UP',
    backend: 'A',
    port: PORT,
    timestamp: new Date().toISOString()
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
