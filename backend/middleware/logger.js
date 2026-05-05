'use strict';

function sanitizeBody(body) {
  if (!body || typeof body !== 'object') return null;
  const sanitized = { ...body };
  if (sanitized.reportText) {
    sanitized.reportText = `[${sanitized.reportText.length} chars]`;
  }
  if (sanitized.imagePath) {
    sanitized.imagePath = '[path]';
  }
  if (sanitized.content && sanitized.content.length > 100) {
    sanitized.content = `[${sanitized.content.length} chars]`;
  }
  return sanitized;
}

function requestLogger(req, res, next) {
  const start = Date.now();

  res.on('finish', () => {
    const durationMs = Date.now() - start;
    const log = {
      timestamp: new Date().toISOString(),
      method: req.method,
      route: req.path,
      userId: req.userId ?? 'unauthenticated',
      status: res.statusCode,
      durationMs,
      body: sanitizeBody(req.body),
    };
    console.log(JSON.stringify(log));
  });

  next();
}

function errorLogger(err, req, res, next) {
  console.error(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'ERROR',
    method: req.method,
    route: req.path,
    userId: req.userId ?? 'unauthenticated',
    error: err.message,
    stack: err.stack,
  }));
  res.status(500).json({ error: 'Internal server error' });
}

module.exports = { requestLogger, errorLogger };
