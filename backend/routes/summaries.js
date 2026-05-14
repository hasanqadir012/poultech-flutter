'use strict';

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { generateWeeklySummary } = require('../services/summary_service');

let db;

function initDb(database) {
  db = database;
}

// POST /summaries/generate — idempotent: returns existing summary if already generated for this period
router.post('/generate', async (req, res) => {
  try {
    const { weekStart, weekEnd } = req.body;

    if (!weekStart || !weekEnd) {
      return res.status(400).json({ error: 'weekStart and weekEnd are required.' });
    }

    const weekStartDate = new Date(weekStart);
    const weekEndDate = new Date(weekEnd);

    if (isNaN(weekStartDate.getTime()) || isNaN(weekEndDate.getTime())) {
      return res.status(400).json({ error: 'Invalid weekStart or weekEnd date format.' });
    }

    // Idempotency: check if a summary for this user + week already exists
    // Compare by normalizing weekStart to its calendar date (year/month/day)
    const dayStart = new Date(weekStartDate);
    dayStart.setHours(0, 0, 0, 0);
    const dayEnd = new Date(weekStartDate);
    dayEnd.setHours(23, 59, 59, 999);

    const existing = await db.collection('summaries').findOne({
      userId: req.userId,
      weekStart: { $gte: dayStart, $lte: dayEnd },
    });

    if (existing) {
      console.log(
        `[SUMMARY] POST /generate — existing found for userId: ${req.userId}, ` +
        `weekStart: ${weekStartDate.toISOString()}`,
      );
      return res.json(existing);
    }

    const summary = await generateWeeklySummary(req.userId, weekStartDate, weekEndDate, db);

    if (!summary) {
      console.log(`[SUMMARY] POST /generate — no reports in period, userId: ${req.userId}`);
      return res.json({ hasData: false });
    }

    console.log(`[SUMMARY] POST /generate — created id: ${summary._id}, userId: ${req.userId}`);
    res.status(201).json(summary);
  } catch (err) {
    console.error(`[SUMMARY] POST /generate error: ${err.message}`);
    res.status(500).json({ error: 'Failed to generate summary.' });
  }
});

// GET /summaries/latest — most recent summary for this user
router.get('/latest', async (req, res) => {
  try {
    const summary = await db
      .collection('summaries')
      .findOne({ userId: req.userId }, { sort: { weekStart: -1 } });

    console.log(`[SUMMARY] GET /latest — userId: ${req.userId}, found: ${!!summary}`);
    res.json(summary ?? null);
  } catch (err) {
    console.error(`[SUMMARY] GET /latest error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch summary.' });
  }
});

// GET /summaries — all summaries for this user, newest first
router.get('/', async (req, res) => {
  try {
    const summaries = await db
      .collection('summaries')
      .find({ userId: req.userId })
      .sort({ weekStart: -1 })
      .limit(12)
      .toArray();

    console.log(`[SUMMARY] GET / — userId: ${req.userId}, count: ${summaries.length}`);
    res.json(summaries);
  } catch (err) {
    console.error(`[SUMMARY] GET / error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch summaries.' });
  }
});

// POST /summaries/force-regenerate — DEV/UTILITY route.
// Re-runs Gemini on the most recent summary's existing weekStart/weekEnd so
// users can preview new prompt/AI changes without waiting for the next
// summary day. Critically:
//   • Uses the EXISTING week boundaries (never invents a new week)
//   • Does NOT shift the regular schedule — the next scheduled summary still
//     fires on the user's configured summary day for the new week
//   • Only operates on the latest summary doc; older summaries are untouched
router.post('/force-regenerate', async (req, res) => {
  try {
    const latest = await db
      .collection('summaries')
      .findOne({ userId: req.userId }, { sort: { weekStart: -1 } });

    if (!latest) {
      return res
        .status(404)
        .json({ error: 'No existing summary to regenerate. Run on your summary day first.' });
    }

    const { weekStart, weekEnd, _id: oldId } = latest;

    // Remove only this specific summary — preserves any older history
    await db.collection('summaries').deleteOne({ _id: oldId });

    console.log(
      `[SUMMARY] force-regenerate — userId: ${req.userId}, ` +
      `cleared summary ${oldId} for ${new Date(weekStart).toISOString().slice(0, 10)} → ` +
      `${new Date(weekEnd).toISOString().slice(0, 10)}`,
    );

    // Regenerate using the SAME date range — same data window, fresh AI prose.
    // Silent: user just clicked regenerate, no need to push them a notification.
    const summary = await generateWeeklySummary(req.userId, weekStart, weekEnd, db, { silent: true });

    if (!summary) {
      // Reports might have been deleted; nothing to regenerate. The week is now
      // "empty" — the next scheduled summary day will create the next week's doc.
      return res.json({
        ran: true,
        forced: true,
        regenerated: false,
        reason: 'no_reports_in_period',
      });
    }

    console.log(`[SUMMARY] force-regenerate complete — userId: ${req.userId}, new id: ${summary._id}`);
    res.status(200).json(summary);
  } catch (err) {
    console.error(`[SUMMARY] force-regenerate error: ${err.message}`);
    res.status(500).json({ error: 'Failed to force regenerate summary.' });
  }
});

// PATCH /summaries/:id/read — mark as read
router.patch('/:id/read', async (req, res) => {
  try {
    const { id } = req.params;
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid summary ID.' });
    }

    const result = await db.collection('summaries').updateOne(
      { _id: new ObjectId(id), userId: req.userId },
      { $set: { isRead: true } },
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({ error: 'Not found or not authorized.' });
    }

    console.log(`[SUMMARY] Marked read — id: ${id}, userId: ${req.userId}`);
    res.json({ success: true });
  } catch (err) {
    console.error(`[SUMMARY] PATCH /:id/read error: ${err.message}`);
    res.status(500).json({ error: 'Failed to mark as read.' });
  }
});

module.exports = { router, initDb };
