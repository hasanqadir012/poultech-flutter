'use strict';

const { TREND_DAILY_STATS_WINDOW, RECS_RECENT_REPORTS } = require('../config');
const { getPktNow, getPktMidnightAsUtc, aggregateTodayStats, backfillMissedDays } = require('./daily_stats_service');
const { generateTrendFromDailyStats } = require('./trend_service');
const { generateRecommendations } = require('./recommendation_service');
const { sendNotification } = require('./notification_service');

// Convert a trend direction enum to a human-readable label for notifications
function prettifyTrend(direction) {
  const map = {
    strong_improvement: 'Strong Improvement',
    improving: 'Improving',
    stable: 'Stable',
    declining: 'Declining',
    strong_decline: 'Strong Decline',
    insufficient_data: 'Insufficient Data',
  };
  return map[direction] || direction || 'Updated';
}

// Main daily analysis orchestrator.
// Aggregates today's detections, generates trend and recommendations.
// Idempotent: skips if trend already generated during today's PKT day.
//
// @param {boolean} silent — when true, skip user-facing FCM notifications.
//   Used by force-regenerate routes since the user is actively watching.
async function runDailyAnalysis(userId, db, { silent = false } = {}) {
  console.log(`[DAILY_ANALYSIS] Starting — userId: ${userId}, silent: ${silent}`);

  // Guard: if a trend was already generated during today's PKT day, skip.
  // Prevents duplicates when multiple requests slip through shouldRunAnalysis concurrently.
  const todayPktMidnight = getPktMidnightAsUtc(getPktNow());
  const existingTrend = await db.collection('trends').findOne({
    userId,
    generatedAt: { $gte: todayPktMidnight },
  });
  if (existingTrend) {
    console.log(`[DAILY_ANALYSIS] Trend already generated today — skipping. userId: ${userId}`);
    return null;
  }

  // 1a. Backfill any past days (last 7) that have orphaned reports but no
  //     daily_stats — recovers data when analysis never ran on a previous day.
  await backfillMissedDays(userId, db, 7);

  // 1b. Aggregate today's reports into daily_stats (may be null if 0 today —
  //     that's OK: backfilled past days still let us generate a trend)
  const todayStats = await aggregateTodayStats(userId, db);

  // 2. Fetch daily_stats sorted oldest→newest for trend computation
  const dailyStats = await db
    .collection('daily_stats')
    .find({ userId })
    .sort({ date: 1 })
    .limit(TREND_DAILY_STATS_WINDOW)
    .toArray();

  if (dailyStats.length < 1) {
    console.log(`[DAILY_ANALYSIS] No daily_stats found (today or backfill) — skipping. userId: ${userId}`);
    return null;
  }

  // 3. Generate trend from daily averages
  let trend = null;
  try {
    trend = await generateTrendFromDailyStats(userId, dailyStats, db);
  } catch (err) {
    console.error(`[DAILY_ANALYSIS] Trend generation failed — userId: ${userId}: ${err.message}`);
  }

  // 3a. Notify the user about the new trend (skip if force-regen or insufficient)
  if (trend && !silent && trend.trend !== 'insufficient_data') {
    const avgPct = (trend.averageFertilityRate * 100).toFixed(1);
    await sendNotification(userId, db, {
      title: "Today's Trend Ready",
      body: `${prettifyTrend(trend.trend)} at ${avgPct}% average over ${trend.windowDays} day${trend.windowDays === 1 ? '' : 's'}. Tap to view the chart.`,
      data: { type: 'trend', screen: 'trends' },
    });
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
      const recsDoc = await generateRecommendations(userId, trend, recentReports, db);

      // 4a. Notify after recommendations save (skip if force-regen)
      if (recsDoc && !silent) {
        const count = (recsDoc.recommendations || []).length;
        if (count > 0) {
          await sendNotification(userId, db, {
            title: `${count} New Recommendation${count === 1 ? '' : 's'}`,
            body: 'Fresh AI suggestions based on today\'s data. Tap to view.',
            data: { type: 'recommendations', screen: 'recommendations' },
          });
        }
      }
    } catch (err) {
      console.error(`[DAILY_ANALYSIS] Recommendations failed — userId: ${userId}: ${err.message}`);
    }
  }

  console.log(`[DAILY_ANALYSIS] Complete — userId: ${userId}, today detections: ${todayStats?.detectionCount ?? 0}, dailyStats: ${dailyStats.length}`);
  return todayStats ?? dailyStats[dailyStats.length - 1];
}

module.exports = { runDailyAnalysis };
