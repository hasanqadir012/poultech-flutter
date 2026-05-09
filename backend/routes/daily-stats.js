'use strict';

const express = require('express');
const router = express.Router();
const { DAILY_STATS_CHART_MAX } = require('../config');

let db;

function initDb(database) {
  db = database;
}

// GET /daily-stats?days=14 — returns last N days of daily_stats for chart, oldest first
router.get('/', async (req, res) => {
  try {
    const requested = parseInt(req.query.days ?? '14', 10);
    const days = Math.min(Math.max(requested, 7), DAILY_STATS_CHART_MAX);

    const stats = await db
      .collection('daily_stats')
      .find({ userId: req.userId })
      .sort({ date: -1 })
      .limit(days)
      .toArray();

    // Deduplicate: keep the first (newest generatedAt) per date, in case of race-condition duplicates
    const seen = new Set();
    const deduped = stats.filter((s) => seen.has(s.date) ? false : (seen.add(s.date), true));

    // Return oldest→newest so the chart plots left-to-right in time order
    deduped.reverse();

    console.log(`[DAILY_STATS] GET — userId: ${req.userId}, days: ${days}, found: ${deduped.length}`);
    res.json(deduped);
  } catch (err) {
    console.error(`[DAILY_STATS] GET error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch daily stats.' });
  }
});

module.exports = { router, initDb };
