'use strict';

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

let db;

function initDb(database) {
  db = database;
}

// POST /reports — save a new report
router.post('/', async (req, res) => {
  try {
    const {
      totalEggs, fertileEggs, infertileEggs,
      fertilityRate, reportText, imagePath, batchLabel,
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

    const report = {
      userId: req.userId,  // injected from verified Firebase token — never trust client
      createdAt: new Date(),
      batchLabel: batchLabel ?? null,
      totalEggs,
      fertileEggs,
      infertileEggs,
      fertilityRate,
      reportText,
      imagePath: imagePath ?? null,
    };

    const result = await db.collection('reports').insertOne(report);
    console.log(`[REPORTS] Inserted report — id: ${result.insertedId}, userId: ${req.userId}`);

    res.status(201).json({ _id: result.insertedId, ...report });
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
