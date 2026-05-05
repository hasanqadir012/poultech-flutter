'use strict';

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

let db;

function initDb(database) {
  db = database;
}

// POST /batches — create a new batch (enforces one active per user)
router.post('/', async (req, res) => {
  try {
    const { name, notes } = req.body;

    if (!name || typeof name !== 'string' || name.trim().length === 0) {
      return res.status(400).json({ error: 'Batch name is required.' });
    }

    // Enforce: only one active batch per user at a time
    const existing = await db.collection('batches').findOne({
      userId: req.userId,
      status: 'active',
    });

    if (existing) {
      return res.status(409).json({
        error: 'You already have an active batch. Close it before creating a new one.',
      });
    }

    const batch = {
      userId: req.userId,
      name: name.trim().substring(0, 40),
      notes: notes ? String(notes).trim().substring(0, 200) : null,
      status: 'active',
      createdAt: new Date(),
      closedAt: null,
      totalDetections: 0,
    };

    const result = await db.collection('batches').insertOne(batch);
    console.log(`[BATCHES] Created — id: ${result.insertedId}, userId: ${req.userId}, name: "${batch.name}"`);

    res.status(201).json({ _id: result.insertedId, ...batch });
  } catch (err) {
    console.error(`[BATCHES] POST error: ${err.message}`);
    res.status(500).json({ error: 'Failed to create batch.' });
  }
});

// GET /batches/active — returns active batch or { active: false }
router.get('/active', async (req, res) => {
  try {
    const batch = await db.collection('batches').findOne({
      userId: req.userId,
      status: 'active',
    });

    if (!batch) {
      return res.json({ active: false });
    }

    console.log(`[BATCHES] Active batch — id: ${batch._id}, userId: ${req.userId}`);
    res.json(batch);
  } catch (err) {
    console.error(`[BATCHES] GET /active error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch active batch.' });
  }
});

// GET /batches — all batches for the user, newest first
router.get('/', async (req, res) => {
  try {
    const batches = await db
      .collection('batches')
      .find({ userId: req.userId })
      .sort({ createdAt: -1 })
      .toArray();

    console.log(`[BATCHES] Fetched ${batches.length} batches for userId: ${req.userId}`);
    res.json(batches);
  } catch (err) {
    console.error(`[BATCHES] GET error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch batches.' });
  }
});

// PATCH /batches/:id/close — close a batch (ownership verified)
router.patch('/:id/close', async (req, res) => {
  try {
    const { id } = req.params;

    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid batch ID.' });
    }

    const updated = await db.collection('batches').findOneAndUpdate(
      { _id: new ObjectId(id), userId: req.userId },
      { $set: { status: 'closed', closedAt: new Date() } },
      { returnDocument: 'after' },
    );

    if (!updated) {
      console.warn(`[BATCHES] PATCH /close — not found or unauthorized. id: ${id}, userId: ${req.userId}`);
      return res.status(404).json({ error: 'Batch not found or not authorized.' });
    }

    console.log(`[BATCHES] Closed batch id: ${id}, userId: ${req.userId}`);
    res.json(updated);
  } catch (err) {
    console.error(`[BATCHES] PATCH /close error: ${err.message}`);
    res.status(500).json({ error: 'Failed to close batch.' });
  }
});

module.exports = { router, initDb };
