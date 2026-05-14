'use strict';

require('dotenv').config();

const express = require('express');
const cors = require('cors');
const cron = require('node-cron');
const { MongoClient } = require('mongodb');
const verifyToken = require('./middleware/auth');
const { requestLogger, errorLogger } = require('./middleware/logger');
const { router: reportsRouter, initDb: initReportsDb } = require('./routes/reports');
const { router: chatRouter, initDb: initChatDb } = require('./routes/chat');
const { router: batchesRouter, initDb: initBatchesDb } = require('./routes/batches');
const { router: trendsRouter, initDb: initTrendsDb } = require('./routes/trends');
const { router: summariesRouter, initDb: initSummariesDb } = require('./routes/summaries');
const { router: userSettingsRouter, initDb: initUserSettingsDb } = require('./routes/user-settings');
const { router: dailyStatsRouter, initDb: initDailyStatsDb } = require('./routes/daily-stats');
const { router: agentRouter, initDb: initAgentDb } = require('./routes/agent');
const { getPktNow, getPktHours, getPktMinutes } = require('./services/daily_stats_service');
const { runDailyAnalysis } = require('./services/daily_analysis_service');

const app = express();

app.use(cors());
app.use(express.json({ limit: '10mb' }));
app.use(requestLogger);

// Health check — no auth required
app.get('/health', (req, res) => {
  res.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// All routes require a valid Firebase token
app.use('/reports', verifyToken, reportsRouter);
app.use('/chat', verifyToken, chatRouter);
app.use('/batches', verifyToken, batchesRouter);
app.use('/trends', verifyToken, trendsRouter);
app.use('/summaries', verifyToken, summariesRouter);
app.use('/user-settings', verifyToken, userSettingsRouter);
app.use('/daily-stats', verifyToken, dailyStatsRouter);
app.use('/agent', verifyToken, agentRouter);

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
  await db.collection('batches').createIndex({ userId: 1, createdAt: -1 });
  await db.collection('batches').createIndex({ userId: 1, status: 1 });
  // Legacy 'trends' and 'recommendations' collections are no longer written —
  // the agent_analyses collection holds the new diagnosis + recs together.
  await db.collection('summaries').createIndex({ userId: 1, weekStart: -1 });
  await db.collection('daily_stats').createIndex({ userId: 1, date: -1 });
  await db.collection('agent_analyses').createIndex({ userId: 1, pktDate: -1 });
  await db.collection('agent_analyses').createIndex({ userId: 1, generatedAt: -1 });

  // Inject DB into route handlers
  initReportsDb(db);
  initChatDb(db);
  initBatchesDb(db);
  initTrendsDb(db);
  initSummariesDb(db);
  initUserSettingsDb(db);
  initDailyStatsDb(db);
  initAgentDb(db);

  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: 'Connected to MongoDB — indexes ensured',
    database: 'poultech_db',
  }));

  // Backup cron scheduler — fires every minute, runs analysis for users whose
  // scheduled PKT time matches the current PKT minute.
  // Primary trigger is the Flutter app (POST /trends/run-daily-analysis on app open).
  cron.schedule('* * * * *', async () => {
    try {
      const nowPkt = getPktNow();
      const h = getPktHours(nowPkt);
      const m = getPktMinutes(nowPkt);

      const dueUsers = await db
        .collection('user_settings')
        .find({ analysisHour: h, analysisMinute: m })
        .toArray();

      if (dueUsers.length > 0) {
        console.log(`[CRON] PKT ${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')} — ${dueUsers.length} user(s) scheduled`);
        for (const u of dueUsers) {
          runDailyAnalysis(u._id, db).catch((err) => {
            console.error(`[CRON] runDailyAnalysis failed — userId: ${u._id}: ${err.message}`);
          });
        }
      }
    } catch (err) {
      console.error(`[CRON] Scheduler error: ${err.message}`);
    }
  });

  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: 'Backup cron scheduler started (every minute)',
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
