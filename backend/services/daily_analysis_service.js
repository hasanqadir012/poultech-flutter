'use strict';

const { TREND_DAILY_STATS_WINDOW, RECS_RECENT_REPORTS } = require('../config');
const { aggregateTodayStats } = require('./daily_stats_service');
const { generateTrendFromDailyStats } = require('./trend_service');
const { generateRecommendations } = require('./recommendation_service');

// Main daily analysis orchestrator.
// Aggregates today's detections, generates trend and recommendations.
// Safe to call multiple times — shouldRunAnalysis guards against double-runs.
async function runDailyAnalysis(userId, db) {
  console.log(`[DAILY_ANALYSIS] Starting — userId: ${userId}`);

  // 1. Aggregate today's reports into daily_stats (idempotent upsert)
  const todayStats = await aggregateTodayStats(userId, db);
  if (!todayStats || todayStats.detectionCount === 0) {
    console.log(`[DAILY_ANALYSIS] No detections today — skipping trend+recs. userId: ${userId}`);
    return null;
  }

  // 2. Fetch daily_stats sorted oldest→newest for trend computation
  const dailyStats = await db
    .collection('daily_stats')
    .find({ userId })
    .sort({ date: 1 })
    .limit(TREND_DAILY_STATS_WINDOW)
    .toArray();

  if (dailyStats.length < 1) {
    console.log(`[DAILY_ANALYSIS] No daily_stats found after aggregation — userId: ${userId}`);
    return null;
  }

  // 3. Generate trend from daily averages
  let trend = null;
  try {
    trend = await generateTrendFromDailyStats(userId, dailyStats, db);
  } catch (err) {
    console.error(`[DAILY_ANALYSIS] Trend generation failed — userId: ${userId}: ${err.message}`);
  }

  // 4. Generate recommendations using recent individual reports as context
  //    (recommendation_service expects individual report documents for its prompt)
  if (trend) {
    try {
      const recentReports = await db
        .collection('reports')
        .find({ userId })
        .sort({ createdAt: -1 })
        .limit(RECS_RECENT_REPORTS)
        .toArray();
      await generateRecommendations(userId, trend, recentReports, db);
    } catch (err) {
      console.error(`[DAILY_ANALYSIS] Recommendations failed — userId: ${userId}: ${err.message}`);
    }
  }

  console.log(`[DAILY_ANALYSIS] Complete — userId: ${userId}, detections: ${todayStats.detectionCount}`);
  return todayStats;
}

module.exports = { runDailyAnalysis };
