'use strict';

const { getPktNow, getPktDateString, aggregateTodayStats, backfillMissedDays } = require('./daily_stats_service');
const { runAndSaveAgentAnalysis } = require('./agent_service');

// Main daily analysis orchestrator.
// 1. Aggregate today's detections into daily_stats (deterministic chart data).
// 2. Backfill any orphaned past days.
// 3. Run the agent — autonomously diagnoses + recommends from the data.
// Idempotent: skips agent run if today's agent_analyses doc already exists.
async function runDailyAnalysis(userId, db) {
  console.log(`[DAILY_ANALYSIS] Starting — userId: ${userId}`);

  const todayPkt = getPktDateString(getPktNow());

  // Guard: if today's agent analysis already exists, skip.
  // Prevents duplicate Gemini calls when multiple triggers fire concurrently.
  const existingAgent = await db.collection('agent_analyses').findOne({
    userId,
    pktDate: todayPkt,
  });
  if (existingAgent) {
    console.log(`[DAILY_ANALYSIS] Agent analysis already exists for today — skipping. userId: ${userId}`);
    return null;
  }

  // 1a. Backfill any past days (last 7) that have orphaned reports but no
  //     daily_stats — recovers data when analysis never ran on a previous day.
  await backfillMissedDays(userId, db, 7);

  // 1b. Aggregate today's reports into daily_stats. May be null if 0 today —
  //     agent can still investigate backfilled history.
  const todayStats = await aggregateTodayStats(userId, db);

  // 2. Run the agent. It autonomously decides which tools to call and produces
  //    a structured diagnosis with evidence + recommendations.
  let agentAnalysis = null;
  try {
    agentAnalysis = await runAndSaveAgentAnalysis(userId, db);
  } catch (err) {
    console.error(`[DAILY_ANALYSIS] Agent failed — userId: ${userId}: ${err.message}`);
  }

  console.log(
    `[DAILY_ANALYSIS] Complete — userId: ${userId}, ` +
    `today detections: ${todayStats?.detectionCount ?? 0}, ` +
    `agent severity: ${agentAnalysis?.severity ?? 'n/a'}`,
  );

  return agentAnalysis;
}

module.exports = { runDailyAnalysis };
