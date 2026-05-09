'use strict';

const express = require('express');
const router = express.Router();
const { getTodayLive, shouldRunAnalysis } = require('../services/daily_stats_service');
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

module.exports = { router, initDb };
