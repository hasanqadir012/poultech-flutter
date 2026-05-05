'use strict';

const express = require('express');
const router = express.Router();

let db;

function initDb(database) {
  db = database;
}

// GET /user-settings — returns the user's analysis time preference
router.get('/', async (req, res) => {
  try {
    const settings = await db.collection('user_settings').findOne({ _id: req.userId });
    const result = {
      analysisHour: settings ? settings.analysisHour : 21,
      analysisMinute: settings ? settings.analysisMinute : 0,
    };
    console.log(`[USER_SETTINGS] GET — userId: ${req.userId}, time: ${result.analysisHour}:${String(result.analysisMinute).padStart(2, '0')}`);
    res.json(result);
  } catch (err) {
    console.error(`[USER_SETTINGS] GET error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch settings.' });
  }
});

// POST /user-settings — upserts the user's analysis time preference
router.post('/', async (req, res) => {
  try {
    const { analysisHour, analysisMinute } = req.body;

    if (
      typeof analysisHour !== 'number' ||
      typeof analysisMinute !== 'number' ||
      analysisHour < 0 || analysisHour > 23 ||
      analysisMinute < 0 || analysisMinute > 59
    ) {
      return res.status(400).json({ error: 'analysisHour (0-23) and analysisMinute (0-59) are required.' });
    }

    await db.collection('user_settings').updateOne(
      { _id: req.userId },
      { $set: { analysisHour, analysisMinute, updatedAt: new Date() } },
      { upsert: true },
    );

    console.log(`[USER_SETTINGS] Saved — userId: ${req.userId}, time: ${analysisHour}:${String(analysisMinute).padStart(2, '0')}`);
    res.json({ success: true, analysisHour, analysisMinute });
  } catch (err) {
    console.error(`[USER_SETTINGS] POST error: ${err.message}`);
    res.status(500).json({ error: 'Failed to save settings.' });
  }
});

module.exports = { router, initDb };
