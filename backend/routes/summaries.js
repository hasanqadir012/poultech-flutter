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
