'use strict';

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const { MongoClient } = require('mongodb');
const verifyToken = require('./middleware/auth');
const { requestLogger, errorLogger } = require('./middleware/logger');
const { router: reportsRouter, initDb: initReportsDb } = require('./routes/reports');
const { router: chatRouter, initDb: initChatDb } = require('./routes/chat');

const app = express();

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(requestLogger);

// Health check — no auth required
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// All report and chat routes require a valid Firebase token
app.use('/reports', verifyToken, reportsRouter);
app.use('/chat', verifyToken, chatRouter);

// Global error handler (logs + returns 500)
app.use(errorLogger);

async function start() {
  const mongoUri = process.env.MONGODB_URI;
  if (!mongoUri) {
    console.error('[SERVER] MONGODB_URI is not set. Check your .env file.');
    process.exit(1);
  }

  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: 'Connecting to MongoDB...',
  }));

  const client = new MongoClient(mongoUri);
  await client.connect();

  const db = client.db('poultech_db');

  // Create indexes for fast per-user queries
  await db.collection('reports').createIndex({ userId: 1, createdAt: -1 });
  await db.collection('chat_sessions').createIndex({ userId: 1, updatedAt: -1 });

  // Inject DB into route handlers
  initReportsDb(db);
  initChatDb(db);

  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: 'Connected to MongoDB — indexes ensured',
    database: 'poultech_db',
  }));

  const port = parseInt(process.env.PORT ?? '3000', 10);
  app.listen(port, () => {
    console.log(JSON.stringify({
      timestamp: new Date().toISOString(),
      level: 'INFO',
      message: `PoulTech API running on port ${port}`,
      port,
    }));
  });
}

start().catch((err) => {
  console.error(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'FATAL',
    error: err.message,
    stack: err.stack,
  }));
  process.exit(1);
});
