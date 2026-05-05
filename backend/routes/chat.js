'use strict';

const express = require('express');
const router = express.Router();
const { ObjectId } = require('mongodb');

let db;

function initDb(database) {
  db = database;
}

// POST /chat/sessions — create a new chat session
router.post('/sessions', async (req, res) => {
  try {
    const now = new Date();
    const session = {
      userId: req.userId,
      startedAt: now,
      updatedAt: now,
      messages: [],
    };

    const result = await db.collection('chat_sessions').insertOne(session);
    console.log(`[CHAT] Created session — id: ${result.insertedId}, userId: ${req.userId}`);
    res.status(201).json({ _id: result.insertedId, ...session });
  } catch (err) {
    console.error(`[CHAT] POST /sessions error: ${err.message}`);
    res.status(500).json({ error: 'Failed to create chat session.' });
  }
});

// POST /chat/sessions/:id/messages — append a message to a session
router.post('/sessions/:id/messages', async (req, res) => {
  try {
    const { id } = req.params;
    const { role, content, timestamp } = req.body;

    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid session ID.' });
    }
    if (!['user', 'assistant'].includes(role)) {
      return res.status(400).json({ error: 'Role must be "user" or "assistant".' });
    }
    if (typeof content !== 'string' || content.trim().length === 0) {
      return res.status(400).json({ error: 'Message content is required.' });
    }

    const message = {
      role,
      content,
      timestamp: timestamp ? new Date(timestamp) : new Date(),
    };

    const result = await db.collection('chat_sessions').updateOne(
      { _id: new ObjectId(id), userId: req.userId },
      {
        $push: { messages: message },
        $set: { updatedAt: new Date() },
      },
    );

    if (result.matchedCount === 0) {
      console.warn(`[CHAT] appendMessage — session not found. id: ${id}, userId: ${req.userId}`);
      return res.status(404).json({ error: 'Session not found or not authorized.' });
    }

    console.log(`[CHAT] Appended ${role} message to session ${id}`);
    res.json({ success: true });
  } catch (err) {
    console.error(`[CHAT] POST /sessions/:id/messages error: ${err.message}`);
    res.status(500).json({ error: 'Failed to append message.' });
  }
});

// GET /chat/sessions — fetch sessions for the logged-in user (newest first)
router.get('/sessions', async (req, res) => {
  try {
    const limit = parseInt(req.query.limit ?? '20', 10);

    const sessions = await db
      .collection('chat_sessions')
      .find({ userId: req.userId })
      .sort({ updatedAt: -1 })
      .limit(limit)
      .toArray();

    console.log(`[CHAT] Fetched ${sessions.length} sessions for userId: ${req.userId}`);
    res.json(sessions);
  } catch (err) {
    console.error(`[CHAT] GET /sessions error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch sessions.' });
  }
});

// GET /chat/sessions/:id — fetch a single session with all messages
router.get('/sessions/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid session ID.' });
    }

    const session = await db.collection('chat_sessions').findOne({
      _id: new ObjectId(id),
      userId: req.userId,
    });

    if (!session) {
      return res.status(404).json({ error: 'Session not found.' });
    }

    console.log(`[CHAT] Fetched session ${id} — messages: ${session.messages.length}`);
    res.json(session);
  } catch (err) {
    console.error(`[CHAT] GET /sessions/:id error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch session.' });
  }
});

// DELETE /chat/sessions/:id — delete a session
router.delete('/sessions/:id', async (req, res) => {
  try {
    const { id } = req.params;

    if (!ObjectId.isValid(id)) {
      return res.status(400).json({ error: 'Invalid session ID.' });
    }

    const result = await db.collection('chat_sessions').deleteOne({
      _id: new ObjectId(id),
      userId: req.userId,
    });

    if (result.deletedCount === 0) {
      return res.status(404).json({ error: 'Session not found or not authorized.' });
    }

    console.log(`[CHAT] Deleted session id: ${id}, userId: ${req.userId}`);
    res.json({ success: true });
  } catch (err) {
    console.error(`[CHAT] DELETE /sessions/:id error: ${err.message}`);
    res.status(500).json({ error: 'Failed to delete session.' });
  }
});

module.exports = { router, initDb };
