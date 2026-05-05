'use strict';

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');
const { shouldRunAnalysis } = require('../services/daily_stats_service');
const { runDailyAnalysis } = require('../services/daily_analysis_service');

let db;

function initDb(database) {
  db = database;
}

// POST /reports — save a new report
router.post('/', async (req, res) => {
  try {
    const {
      totalEggs, fertileEggs, infertileEggs,
      fertilityRate, reportText, imagePath,
    } = req.body;

    // Basic validation
    if (
      typeof totalEggs !== 'number' ||
      typeof fertileEggs !== 'number' ||
      typeof infertileEggs !== 'number' ||
      typeof fertilityRate !== 'number' ||
      typeof reportText !== 'string'
    ) {
      return res.status(400).json({ error: 'Missing or invalid required fields.' });
    }

    // Look up the user's active batch — server-side, not trusted from client
    const activeBatch = await db.collection('batches').findOne({
      userId: req.userId,
      status: 'active',
    });

    const report = {
      userId: req.userId,  // injected from verified Firebase token — never trust client
      createdAt: new Date(),
      batchId: activeBatch ? activeBatch._id.toString() : null,
      batchLabel: activeBatch ? activeBatch.name : null,
      totalEggs,
      fertileEggs,
      infertileEggs,
      fertilityRate,
      reportText,
      imagePath: imagePath ?? null,
    };

    const result = await db.collection('reports').insertOne(report);
    console.log(`[REPORTS] Inserted report — id: ${result.insertedId}, userId: ${req.userId}, batchId: ${report.batchId ?? 'none'}`);

    // Increment totalDetections on the active batch
    if (activeBatch) {
      await db.collection('batches').updateOne(
        { _id: activeBatch._id },
        { $inc: { totalDetections: 1 } },
      );
      console.log(`[REPORTS] Incremented totalDetections for batch: ${activeBatch._id}`);
    }

    res.status(201).json({ _id: result.insertedId, ...report });

    // Fire-and-forget catch-up: if it's past the user's analysis time and today's
    // analysis hasn't run yet, run it now. Handles cases where the app was closed
    // when analysis time passed or Railway was temporarily down.
    shouldRunAnalysis(req.userId, db).then((should) => {
      if (should) return runDailyAnalysis(req.userId, db);
    }).catch(() => {});
  } catch (err) {
    console.error(`[REPORTS] POST error: ${err.message}`);
    res.status(500).json({ error: 'Failed to save report.' });
  }
});

// GET /reports — fetch all reports for the logged-in user
router.get('/', async (req, res) => {
  try {
    const reports = await db
      .collection('reports')
      .find({ userId: req.userId })
      .sort({ createdAt: -1 })
      .limit(50)
      .toArray();

    console.log(`[REPORTS] Fetched ${reports.length} reports for userId: ${req.userId}`);
    res.json(reports);
  } catch (err) {
    console.error(`[REPORTS] GET error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch reports.' });
  }
});

// DELETE /reports/:id — delete a report (ownership verified)
router.delete('/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid report ID.' });
    }

    const result = await db.collection('reports').deleteOne({
      _id: new ObjectId(id),
      userId: req.userId,  // prevents deleting another user's report
    });

    if (result.deletedCount === 0) {
      console.warn(`[REPORTS] DELETE — not found or unauthorized. id: ${id}, userId: ${req.userId}`);
      return res.status(404).json({ error: 'Report not found or not authorized.' });
    }

    console.log(`[REPORTS] Deleted report id: ${id}, userId: ${req.userId}`);
    res.json({ success: true });
  } catch (err) {
    console.error(`[REPORTS] DELETE error: ${err.message}`);
    res.status(500).json({ error: 'Failed to delete report.' });
  }
});

module.exports = { router, initDb };
