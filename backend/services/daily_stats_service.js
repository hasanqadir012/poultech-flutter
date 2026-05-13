'use strict';

const PKT_OFFSET_MS = 5 * 60 * 60 * 1000; // UTC+5

// All PKT calculations use UTC methods (getUTCXxx, Date.UTC) so they are
// independent of the Node.js process timezone. getPktNow() returns a Date
// whose UTC clock components represent the PKT clock.
function getPktNow() {
  return new Date(Date.now() + PKT_OFFSET_MS);
}

function getPktDateString(pktDate) {
  return pktDate.toISOString().slice(0, 10); // YYYY-MM-DD in PKT
}

function getPktHours(pktDate) {
  return pktDate.getUTCHours();
}

function getPktMinutes(pktDate) {
  return pktDate.getUTCMinutes();
}

// Given a Date whose UTC clock represents a PKT time, return the actual UTC
// instant of that PKT date's midnight. Uses UTC methods to avoid local-TZ bugs.
function getPktMidnightAsUtc(pktDate) {
  const y = pktDate.getUTCFullYear();
  const m = pktDate.getUTCMonth();
  const d = pktDate.getUTCDate();
  return new Date(Date.UTC(y, m, d) - PKT_OFFSET_MS);
}

// PKT midnight (as UTC) for an arbitrary "YYYY-MM-DD" PKT date string
function pktDateStringToMidnightUtc(pktDateStr) {
  const [y, m, d] = pktDateStr.split('-').map(Number);
  return new Date(Date.UTC(y, m - 1, d) - PKT_OFFSET_MS);
}

// Aggregate reports for a specific PKT date into a daily_stats document.
// Idempotent upsert keyed by {userId, date}.
async function aggregateStatsForDate(userId, db, pktDateStr) {
  const dateStart = pktDateStringToMidnightUtc(pktDateStr);
  const dateEnd = new Date(dateStart.getTime() + 24 * 60 * 60 * 1000 - 1);

  const reports = await db
    .collection('reports')
    .find({ userId, createdAt: { $gte: dateStart, $lte: dateEnd } })
    .toArray();

  if (reports.length === 0) return null;

  const detectionCount = reports.length;
  const totalEggs = reports.reduce((s, r) => s + r.totalEggs, 0);
  const fertileEggs = reports.reduce((s, r) => s + r.fertileEggs, 0);
  const infertileEggs = reports.reduce((s, r) => s + r.infertileEggs, 0);
  const rates = reports.map((r) => r.fertilityRate);
  const averageFertilityRate = rates.reduce((a, b) => a + b, 0) / rates.length;
  const highestRate = Math.max(...rates);
  const lowestRate = Math.min(...rates);

  const doc = {
    userId,
    date: pktDateStr,
    dateStart,
    dateEnd,
    detectionCount,
    totalEggs,
    fertileEggs,
    infertileEggs,
    averageFertilityRate,
    highestRate,
    lowestRate,
    generatedAt: new Date(),
  };

  await db.collection('daily_stats').updateOne(
    { userId, date: pktDateStr },
    { $set: doc },
    { upsert: true },
  );

  console.log(
    `[DAILY_STATS] Saved — userId: ${userId}, date: ${pktDateStr}, ` +
    `detections: ${detectionCount}, avgRate: ${(averageFertilityRate * 100).toFixed(1)}%`,
  );

  return doc;
}

// Aggregate today's reports
async function aggregateTodayStats(userId, db) {
  const todayDateStr = getPktDateString(getPktNow());
  const result = await aggregateStatsForDate(userId, db, todayDateStr);
  if (!result) console.log(`[DAILY_STATS] No reports today — userId: ${userId}`);
  return result;
}

// Backfill any past days (within `daysBack`) that have reports but no daily_stats.
// Recovers orphaned reports when analysis failed to run on a given day.
async function backfillMissedDays(userId, db, daysBack = 7) {
  const nowPkt = getPktNow();
  const created = [];

  for (let i = 1; i <= daysBack; i++) {
    const targetPkt = new Date(nowPkt.getTime() - i * 24 * 60 * 60 * 1000);
    const dateStr = getPktDateString(targetPkt);

    const existing = await db.collection('daily_stats').findOne({ userId, date: dateStr });
    if (existing) continue;

    const doc = await aggregateStatsForDate(userId, db, dateStr);
    if (doc) created.push(dateStr);
  }

  if (created.length > 0) {
    console.log(`[BACKFILL] Recovered ${created.length} missed day(s) — userId: ${userId}, dates: ${created.join(', ')}`);
  }
  return created;
}

// Returns today's live running average WITHOUT saving to DB
async function getTodayLive(userId, db) {
  const nowPkt = getPktNow();
  const dateStart = getPktMidnightAsUtc(nowPkt);
  const dateEnd = new Date(dateStart.getTime() + 24 * 60 * 60 * 1000 - 1);

  const reports = await db
    .collection('reports')
    .find({ userId, createdAt: { $gte: dateStart, $lte: dateEnd } })
    .toArray();

  if (reports.length === 0) {
    return { hasData: false, detectionCount: 0, averageFertilityRate: 0, totalEggs: 0, fertileEggs: 0, infertileEggs: 0 };
  }

  const detectionCount = reports.length;
  const totalEggs = reports.reduce((s, r) => s + r.totalEggs, 0);
  const fertileEggs = reports.reduce((s, r) => s + r.fertileEggs, 0);
  const infertileEggs = reports.reduce((s, r) => s + r.infertileEggs, 0);
  const rates = reports.map((r) => r.fertilityRate);
  const averageFertilityRate = rates.reduce((a, b) => a + b, 0) / rates.length;

  return { hasData: true, detectionCount, averageFertilityRate, totalEggs, fertileEggs, infertileEggs };
}

// Returns true if daily analysis should run for this user right now:
//   1. Current PKT time >= user's scheduled analysisHour:analysisMinute (default 21:00)
//   2. No daily_stats doc exists yet for today (PKT date)
async function shouldRunAnalysis(userId, db) {
  const nowPkt = getPktNow();
  const todayDateStr = getPktDateString(nowPkt);

  const settings = await db.collection('user_settings').findOne({ _id: userId });
  const scheduledHour = settings ? settings.analysisHour : 21;
  const scheduledMinute = settings ? settings.analysisMinute : 0;

  // Use UTC methods on pktDate (UTC offset already applied) — timezone-safe
  const nowMinutes = getPktHours(nowPkt) * 60 + getPktMinutes(nowPkt);
  const scheduledMinutes = scheduledHour * 60 + scheduledMinute;

  if (nowMinutes < scheduledMinutes) return false;

  const existing = await db.collection('daily_stats').findOne({ userId, date: todayDateStr });
  return !existing;
}

module.exports = {
  getPktNow,
  getPktHours,
  getPktMinutes,
  getPktDateString,
  getPktMidnightAsUtc,
  aggregateStatsForDate,
  aggregateTodayStats,
  backfillMissedDays,
  getTodayLive,
  shouldRunAnalysis,
};
