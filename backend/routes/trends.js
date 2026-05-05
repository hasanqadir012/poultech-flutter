'use strict';

const express = require('express');
const router = express.Router();
const { getTodayLive, shouldRunAnalysis } = require('../services/daily_stats_service');
const { runDailyAnalysis } = require('../services/daily_analysis_service');

let db;

function initDb(database) {
  db = database;
}

// GET /trends/latest?days=N — most recent trend for this user with the given window
router.get('/latest', async (req, res) => {
  try {
    const windowDays = parseInt(req.query.days ?? '14', 10);
    const validWindows = [7, 14, 30];
    const days = validWindows.includes(windowDays) ? windowDays : 14;

    const trend = await db
      .collection('trends')
      .findOne(
        { userId: req.userId, windowDays: days },
        { sort: { generatedAt: -1 } },
      );

    console.log(
      `[TRENDS] GET /latest — userId: ${req.userId}, days: ${days}, found: ${!!trend}`,
    );
    res.json(trend ?? null);
  } catch (err) {
    console.error(`[TRENDS] GET /latest error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch trend.' });
  }
});

// GET /trends — full trend history for this user, newest first
router.get('/', async (req, res) => {
  try {
    const trends = await db
      .collection('trends')
      .find({ userId: req.userId })
      .sort({ generatedAt: -1 })
      .limit(20)
      .toArray();

    console.log(`[TRENDS] GET / — userId: ${req.userId}, count: ${trends.length}`);
    res.json(trends);
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
