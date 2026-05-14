'use strict';

const express = require('express');
const router = express.Router();
const { getTodayLive } = require('../services/daily_stats_service');

let db;

function initDb(database) {
  db = database;
}

// GET /trends/today — live running average of today's detections (no save, no Gemini).
// Powers the hollow "today" dot on the fertility chart and the today-live card.
// All other legacy trend endpoints (latest, history, run-daily-analysis,
// force-regenerate) were removed when the system became fully agentic.
router.get('/today', async (req, res) => {
  try {
    const live = await getTodayLive(req.userId, db);
    console.log(
      `[TRENDS] GET /today — userId: ${req.userId}, hasData: ${live.hasData}, count: ${live.detectionCount}`,
    );
    res.json(live);
  } catch (err) {
    console.error(`[TRENDS] GET /today error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch today live data.' });
  }
});

module.exports = { router, initDb };
