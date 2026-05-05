'use strict';

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

let db;

function initDb(database) {
  db = database;
}

// GET /recommendations/latest — most recent recommendations document for this user
router.get('/latest', async (req, res) => {
  try {
    const rec = await db
      .collection('recommendations')
      .findOne({ userId: req.userId }, { sort: { generatedAt: -1 } });

    console.log(
      `[RECOMMEND] GET /latest — userId: ${req.userId}, found: ${!!rec}`,
    );
    res.json(rec ?? null);
  } catch (err) {
    console.error(`[RECOMMEND] GET /latest error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch recommendations.' });
  }
});

// PATCH /recommendations/:id/read — mark a recommendations document as read
router.patch('/:id/read', async (req, res) => {
  try {
    const { id } = req.params;
    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid recommendation ID.' });
    }

    const result = await db.collection('recommendations').updateOne(
      { _id: new ObjectId(id), userId: req.userId },
      { $set: { isRead: true } },
    );

    if (result.matchedCount === 0) {
      return res.status(404).json({ error: 'Not found or not authorized.' });
    }

    console.log(`[RECOMMEND] Marked read — id: ${id}, userId: ${req.userId}`);
    res.json({ success: true });
  } catch (err) {
    console.error(`[RECOMMEND] PATCH /:id/read error: ${err.message}`);
    res.status(500).json({ error: 'Failed to mark as read.' });
  }
});

module.exports = { router, initDb };
