'use strict';

const express = require('express');
const router = express.Router();
const { getTodayLive, shouldRunAnalysis, backfillMissedDays } = require('../services/daily_stats_service');
const { runDailyAnalysis } = require('../services/daily_analysis_service');

let db;

function initDb(database) {
  db = database;
}

// GET /trends/latest — most recent trend for this user (windowDays filter removed:
// stored windowDays = actual data length, not user's chart selector, so filtering
// by it caused new users to never see trends)
router.get('/latest', async (req, res) => {
  try {
    const trend = await db
      .collection('trends')
      .findOne(
        { userId: req.userId },
        { sort: { generatedAt: -1 } },
      );

    console.log(
      `[TRENDS] GET /latest — userId: ${req.userId}, found: ${!!trend}, windowDays: ${trend?.windowDays ?? 'n/a'}`,
    );
    res.json(trend ?? null);
  } catch (err) {
    console.error(`[TRENDS] GET /latest error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch trend.' });
  }
});

const PKT_OFFSET_MS = 5 * 60 * 60 * 1000;

// GET /trends — full trend history for this user, newest first (one per PKT day)
router.get('/', async (req, res) => {
  try {
    const trends = await db
      .collection('trends')
      .find({ userId: req.userId })
      .sort({ generatedAt: -1 })
      .limit(60)
      .toArray();

    // Deduplicate: keep the first (most recent) trend per PKT day
    const seen = new Set();
    const deduped = trends.filter((t) => {
      const pktDate = new Date(t.generatedAt.getTime() + PKT_OFFSET_MS).toISOString().slice(0, 10);
      return seen.has(pktDate) ? false : (seen.add(pktDate), true);
    }).slice(0, 20);

    console.log(`[TRENDS] GET / — userId: ${req.userId}, count: ${deduped.length}`);
    res.json(deduped);
  } catch (err) {
    console.error(`[TRENDS] GET / error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch trends.' });
  }
});

// GET /trends/today — live running average of today's detections (no save, no Gemini)
router.get('/today', async (req, res) => {
  try {
    const live = await getTodayLive(req.userId, db);
    console.log(`[TRENDS] GET /today — userId: ${req.userId}, hasData: ${live.hasData}, count: ${live.detectionCount}`);
    res.json(live);
  } catch (err) {
    console.error(`[TRENDS] GET /today error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch today live data.' });
  }
});

// POST /trends/run-daily-analysis — primary app-open trigger
// Returns { ran: true } if analysis ran, { ran: false, reason } if skipped
router.post('/run-daily-analysis', async (req, res) => {
  try {
    // Always backfill missed past days on app open — recovers orphaned reports
    // even when shouldRunAnalysis would return false (e.g. before scheduled time).
    await backfillMissedDays(req.userId, db, 7).catch((err) =>
      console.error(`[TRENDS] backfill failed — userId: ${req.userId}: ${err.message}`),
    );

    const should = await shouldRunAnalysis(req.userId, db);
    if (!should) {
      const nowPkt = new Date(Date.now() + 5 * 60 * 60 * 1000);
      const todayDateStr = nowPkt.toISOString().slice(0, 10);
      const existing = await db.collection('daily_stats').findOne({ userId: req.userId, date: todayDateStr });
      const reason = existing ? 'already_ran' : 'too_early';
      console.log(`[TRENDS] run-daily-analysis skipped — userId: ${req.userId}, reason: ${reason}`);
      return res.json({ ran: false, reason });
    }

    // Run asynchronously — respond immediately so the app isn't blocked
    res.json({ ran: true });
    runDailyAnalysis(req.userId, db).catch((err) => {
      console.error(`[TRENDS] run-daily-analysis failed — userId: ${req.userId}: ${err.message}`);
    });
  } catch (err) {
    console.error(`[TRENDS] run-daily-analysis error: ${err.message}`);
    res.status(500).json({ error: 'Failed to trigger analysis.' });
  }
});

// POST /trends/force-regenerate — DEV/UTILITY route.
// Clears today's trend and recommendation docs, then re-runs the analysis.
// Bypasses the same-day idempotency guard so you can iterate on prompts/code
// without having to wait until tomorrow.
router.post('/force-regenerate', async (req, res) => {
  try {
    const PKT_OFFSET_MS = 5 * 60 * 60 * 1000;
    const nowPkt = new Date(Date.now() + PKT_OFFSET_MS);
    const todayPktMidnightUtc = new Date(
      Date.UTC(nowPkt.getUTCFullYear(), nowPkt.getUTCMonth(), nowPkt.getUTCDate()) - PKT_OFFSET_MS,
    );

    const trendsDeleted = await db.collection('trends').deleteMany({
      userId: req.userId,
      generatedAt: { $gte: todayPktMidnightUtc },
    });
    const recsDeleted = await db.collection('recommendations').deleteMany({
      userId: req.userId,
      generatedAt: { $gte: todayPktMidnightUtc },
    });

    console.log(
      `[TRENDS] force-regenerate — userId: ${req.userId}, ` +
      `cleared trends: ${trendsDeleted.deletedCount}, recs: ${recsDeleted.deletedCount}`,
    );

    res.json({
      ran: true,
      forced: true,
      cleared: { trends: trendsDeleted.deletedCount, recommendations: recsDeleted.deletedCount },
    });

    // silent: true — user is right there tapping refresh; don't push them a
    // notification for an action they just initiated.
    runDailyAnalysis(req.userId, db, { silent: true }).catch((err) => {
      console.error(`[TRENDS] force-regenerate run failed — userId: ${req.userId}: ${err.message}`);
    });
  } catch (err) {
    console.error(`[TRENDS] force-regenerate error: ${err.message}`);
    res.status(500).json({ error: 'Failed to force regenerate.' });
  }
});

module.exports = { router, initDb };
