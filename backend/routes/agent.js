'use strict';

const express = require('express');
const router = express.Router();
const { runAndSaveAgentAnalysis } = require('../services/agent_service');
const { getPktNow, getPktDateString } = require('../services/daily_stats_service');

let db;

function initDb(database) {
  db = database;
}

// GET /agent/latest — most recent agent analysis for this user (any day).
// Used by the dashboard to render the latest diagnosis card.
router.get('/latest', async (req, res) => {
  try {
    const latest = await db
      .collection('agent_analyses')
      .findOne(
        { userId: req.userId },
        { sort: { generatedAt: -1 } },
      );

    console.log(
      `[AGENT_ROUTE] GET /latest — userId: ${req.userId}, found: ${!!latest}, ` +
      `pktDate: ${latest?.pktDate ?? 'n/a'}`,
    );
    res.json(latest ?? null);
  } catch (err) {
    console.error(`[AGENT_ROUTE] GET /latest error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch latest analysis.' });
  }
});

// GET /agent/today — today's agent analysis (PKT day), or null if not yet generated.
router.get('/today', async (req, res) => {
  try {
    const todayPkt = getPktDateString(getPktNow());
    const today = await db
      .collection('agent_analyses')
      .findOne({ userId: req.userId, pktDate: todayPkt });

    console.log(
      `[AGENT_ROUTE] GET /today — userId: ${req.userId}, pktDate: ${todayPkt}, found: ${!!today}`,
    );
    res.json(today ?? null);
  } catch (err) {
    console.error(`[AGENT_ROUTE] GET /today error: ${err.message}`);
    res.status(500).json({ error: 'Failed to fetch today analysis.' });
  }
});

// POST /agent/analyze — runs the agent if today's analysis is not cached.
// Responds immediately (async pattern). Client polls GET /agent/today (or /latest)
// to retrieve the result once generated.
//
// Returns:
//   { ran: false, reason: 'cached', analysis }  — already cached for today
//   { ran: true }                                — analysis triggered in background
router.post('/analyze', async (req, res) => {
  try {
    const todayPkt = getPktDateString(getPktNow());
    const existing = await db
      .collection('agent_analyses')
      .findOne({ userId: req.userId, pktDate: todayPkt });

    if (existing) {
      console.log(
        `[AGENT_ROUTE] POST /analyze — cached hit, userId: ${req.userId}, pktDate: ${todayPkt}`,
      );
      return res.json({ ran: false, reason: 'cached', analysis: existing });
    }

    // Respond immediately, run agent in background.
    res.json({ ran: true });

    runAndSaveAgentAnalysis(req.userId, db).catch((err) => {
      console.error(
        `[AGENT_ROUTE] Background agent run failed — userId: ${req.userId}: ${err.message}`,
      );
    });
  } catch (err) {
    console.error(`[AGENT_ROUTE] POST /analyze error: ${err.message}`);
    res.status(500).json({ error: 'Failed to trigger analysis.' });
  }
});

// POST /agent/force-regenerate — clears today's analysis and runs fresh.
// Useful for iterating on prompts/tools without waiting until tomorrow.
router.post('/force-regenerate', async (req, res) => {
  try {
    const todayPkt = getPktDateString(getPktNow());

    const deleted = await db
      .collection('agent_analyses')
      .deleteOne({ userId: req.userId, pktDate: todayPkt });

    console.log(
      `[AGENT_ROUTE] force-regenerate — userId: ${req.userId}, ` +
      `pktDate: ${todayPkt}, cleared: ${deleted.deletedCount}`,
    );

    res.json({ ran: true, forced: true, cleared: deleted.deletedCount });

    runAndSaveAgentAnalysis(req.userId, db, { silent: true }).catch((err) => {
      console.error(
        `[AGENT_ROUTE] force-regenerate background run failed — userId: ${req.userId}: ${err.message}`,
      );
    });
  } catch (err) {
    console.error(`[AGENT_ROUTE] force-regenerate error: ${err.message}`);
    res.status(500).json({ error: 'Failed to force regenerate.' });
  }
});

module.exports = { router, initDb };
