'use strict';

const PKT_OFFSET_MS = 5 * 60 * 60 * 1000; // UTC+5

function getPktNow() {
  return new Date(Date.now() + PKT_OFFSET_MS);
}

function getPktDateString(pktDate) {
  // Returns "YYYY-MM-DD" in PKT
  return pktDate.toISOString().slice(0, 10);
}

function getPktMidnightAsUtc(pktDate) {
  // Given a Date that represents PKT time, return the UTC equivalent of PKT midnight
  const d = new Date(pktDate);
  d.setHours(0, 0, 0, 0); // zero out hours in PKT
  return new Date(d.getTime() - PKT_OFFSET_MS);
}

// Aggregate today's reports into a daily_stats document (upsert — idempotent)
async function aggregateTodayStats(userId, db) {
  const nowPkt = getPktNow();
  const todayDateStr = getPktDateString(nowPkt);
  const dateStart = getPktMidnightAsUtc(nowPkt);
  const dateEnd = new Date(dateStart.getTime() + 24 * 60 * 60 * 1000 - 1); // 23:59:59.999 PKT in UTC

  const reports = await db
    .collection('reports')
    .find({ userId, createdAt: { $gte: dateStart, $lte: dateEnd } })
    .toArray();

  if (reports.length === 0) {
    console.log(`[DAILY_STATS] No reports today — userId: ${userId}`);
    return null;
  }

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
    date: todayDateStr,
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
    { userId, date: todayDateStr },
    { $set: doc },
    { upsert: true },
  );

  console.log(
    `[DAILY_STATS] Saved — userId: ${userId}, date: ${todayDateStr}, ` +
    `detections: ${detectionCount}, avgRate: ${(averageFertilityRate * 100).toFixed(1)}%`,
  );

  return doc;
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

  const nowMinutes = nowPkt.getHours() * 60 + nowPkt.getMinutes();
  const scheduledMinutes = scheduledHour * 60 + scheduledMinute;

  if (nowMinutes < scheduledMinutes) return false;

  const existing = await db.collection('daily_stats').findOne({ userId, date: todayDateStr });
  return !existing;
}

module.exports = { getPktNow, getPktDateString, aggregateTodayStats, getTodayLive, shouldRunAnalysis };
