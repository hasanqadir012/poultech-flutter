'use strict';

// Pure-function tools the agent can invoke during analysis.
// Each tool returns plain JSON-serializable data that Gemini reads back
// to decide its next action. No side effects, no DB writes.

// Linear regression slope (x = index, y = value). Duplicated locally so this
// module stays decoupled from trend_service.js.
function calcSlope(values) {
  const n = values.length;
  if (n < 2) return 0;
  const sumX = (n * (n - 1)) / 2;
  const sumX2 = (n * (n - 1) * (2 * n - 1)) / 6;
  const sumY = values.reduce((a, b) => a + b, 0);
  const sumXY = values.reduce((sum, y, i) => sum + i * y, 0);
  return (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
}

// Group reports by batch label and compute per-batch averages.
// Duplicated locally to keep this module independent of summary_service.js.
function computeBatchBreakdown(reports) {
  const byLabel = new Map();
  for (const r of reports) {
    const label = r.batchLabel || 'Unlabeled';
    if (!byLabel.has(label)) {
      byLabel.set(label, { count: 0, sumRate: 0, eggs: 0, fertile: 0, firstAt: r.createdAt, lastAt: r.createdAt });
    }
    const b = byLabel.get(label);
    b.count += 1;
    b.sumRate += r.fertilityRate;
    b.eggs += r.totalEggs;
    b.fertile += r.fertileEggs;
    if (r.createdAt < b.firstAt) b.firstAt = r.createdAt;
    if (r.createdAt > b.lastAt) b.lastAt = r.createdAt;
  }
  return Array.from(byLabel.entries())
    .map(([label, b]) => ({
      label,
      detectionCount: b.count,
      avgFertilityRate: b.sumRate / b.count,
      totalEggs: b.eggs,
      fertileEggs: b.fertile,
      firstDetection: b.firstAt.toISOString().slice(0, 10),
      lastDetection: b.lastAt.toISOString().slice(0, 10),
    }))
    .sort((a, b) => b.avgFertilityRate - a.avgFertilityRate);
}

function round(n, dp = 4) {
  return Math.round(n * Math.pow(10, dp)) / Math.pow(10, dp);
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 1: get_recent_reports
// Returns the farmer's most recent detection reports as a flat list.
// ─────────────────────────────────────────────────────────────────────────────
async function getRecentReports(userId, limit, db) {
  const safeLimit = Math.min(Math.max(Number(limit) || 10, 1), 50);

  const reports = await db
    .collection('reports')
    .find({ userId })
    .sort({ createdAt: -1 })
    .limit(safeLimit)
    .toArray();

  return {
    count: reports.length,
    requestedLimit: safeLimit,
    reports: reports.map((r) => ({
      date: new Date(r.createdAt).toISOString().slice(0, 10),
      totalEggs: r.totalEggs,
      fertileEggs: r.fertileEggs,
      infertileEggs: r.infertileEggs,
      fertilityRate: round(r.fertilityRate),
      batchLabel: r.batchLabel || null,
    })),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 2: get_fertility_trend
// Computes direction and slope from daily averages over N days.
// ─────────────────────────────────────────────────────────────────────────────
async function getFertilityTrend(userId, days, db) {
  const safeDays = Math.min(Math.max(Number(days) || 14, 1), 60);

  const dailyStats = await db
    .collection('daily_stats')
    .find({ userId })
    .sort({ date: -1 })
    .limit(safeDays)
    .toArray();

  if (dailyStats.length === 0) {
    return {
      windowDays: 0,
      direction: 'no_data',
      message: 'No daily_stats found. The farmer has not completed any analyzed day yet.',
      dailyAverages: [],
    };
  }

  const ordered = dailyStats.reverse(); // oldest → newest
  const rates = ordered.map((d) => d.averageFertilityRate);
  const totalDetections = ordered.reduce((s, d) => s + d.detectionCount, 0);

  if (ordered.length < 2) {
    return {
      windowDays: ordered.length,
      direction: 'insufficient_data',
      message: 'Only one day of data — need at least 2 days for trend direction.',
      averageFertilityRate: round(rates[0]),
      totalDetections,
      dailyAverages: ordered.map((d) => ({
        date: d.date,
        avgFertilityRate: round(d.averageFertilityRate),
        detections: d.detectionCount,
      })),
    };
  }

  const slope = calcSlope(rates);
  let direction = 'stable';
  if (slope > 0.02) direction = 'improving';
  else if (slope < -0.02) direction = 'declining';

  const absSlope = Math.abs(slope);
  let strength = 'slight';
  if (absSlope > 0.08) strength = 'strong';
  else if (absSlope > 0.04) strength = 'moderate';

  return {
    windowDays: ordered.length,
    direction,
    strength,
    slope: round(slope, 5),
    averageFertilityRate: round(rates.reduce((a, b) => a + b, 0) / rates.length),
    highestDailyAvg: round(Math.max(...ordered.map((d) => d.highestRate))),
    lowestDailyAvg: round(Math.min(...ordered.map((d) => d.lowestRate))),
    firstDayAvg: round(rates[0]),
    lastDayAvg: round(rates[rates.length - 1]),
    totalDetections,
    dailyAverages: ordered.map((d) => ({
      date: d.date,
      avgFertilityRate: round(d.averageFertilityRate),
      detections: d.detectionCount,
    })),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 3: get_batch_performance
// Pass batchLabel → deep-dive that batch. Omit → compare all batches.
// ─────────────────────────────────────────────────────────────────────────────
async function getBatchPerformance(userId, batchLabel, db, daysBack = 30) {
  const cutoff = new Date(Date.now() - daysBack * 24 * 60 * 60 * 1000);
  const query = { userId, createdAt: { $gte: cutoff } };
  if (batchLabel) query.batchLabel = batchLabel;

  const reports = await db.collection('reports').find(query).toArray();

  if (reports.length === 0) {
    return {
      mode: batchLabel ? 'single_batch' : 'all_batches',
      batchLabel: batchLabel || null,
      detectionCount: 0,
      message: batchLabel
        ? `No detections found for batch "${batchLabel}" in the last ${daysBack} days.`
        : `No detections in the last ${daysBack} days.`,
    };
  }

  if (batchLabel) {
    const rates = reports.map((r) => r.fertilityRate);
    const sortedAsc = reports.slice().sort((a, b) => a.createdAt - b.createdAt);
    return {
      mode: 'single_batch',
      batchLabel,
      detectionCount: reports.length,
      avgFertilityRate: round(rates.reduce((a, b) => a + b, 0) / rates.length),
      highestRate: round(Math.max(...rates)),
      lowestRate: round(Math.min(...rates)),
      totalEggs: reports.reduce((s, r) => s + r.totalEggs, 0),
      fertileEggs: reports.reduce((s, r) => s + r.fertileEggs, 0),
      firstDetection: sortedAsc[0].createdAt.toISOString().slice(0, 10),
      lastDetection: sortedAsc[sortedAsc.length - 1].createdAt.toISOString().slice(0, 10),
    };
  }

  const breakdown = computeBatchBreakdown(reports);
  return {
    mode: 'all_batches',
    daysScanned: daysBack,
    totalBatches: breakdown.length,
    batches: breakdown.map((b) => ({
      label: b.label,
      detectionCount: b.detectionCount,
      avgFertilityRate: round(b.avgFertilityRate),
      totalEggs: b.totalEggs,
      fertileEggs: b.fertileEggs,
      firstDetection: b.firstDetection,
      lastDetection: b.lastDetection,
    })),
    bestBatch: breakdown[0]?.label || null,
    worstBatch: breakdown[breakdown.length - 1]?.label || null,
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Tool 4: compare_time_periods
// Compares two consecutive windows ending now (recent vs prior).
// e.g. period1Days=7, period2Days=7 → last 7 days vs the 7 days before that.
// ─────────────────────────────────────────────────────────────────────────────
async function compareTimePeriods(userId, period1Days, period2Days, db) {
  const p1 = Math.min(Math.max(Number(period1Days) || 7, 1), 60);
  const p2 = Math.min(Math.max(Number(period2Days) || 7, 1), 60);

  const now = new Date();
  const recentStart = new Date(now.getTime() - p1 * 24 * 60 * 60 * 1000);
  const priorEnd = recentStart;
  const priorStart = new Date(priorEnd.getTime() - p2 * 24 * 60 * 60 * 1000);

  async function statsFor(start, end) {
    const reports = await db
      .collection('reports')
      .find({ userId, createdAt: { $gte: start, $lt: end } })
      .toArray();
    if (reports.length === 0) return null;
    const rates = reports.map((r) => r.fertilityRate);
    return {
      detectionCount: reports.length,
      avgFertilityRate: round(rates.reduce((a, b) => a + b, 0) / rates.length),
      totalEggs: reports.reduce((s, r) => s + r.totalEggs, 0),
      fertileEggs: reports.reduce((s, r) => s + r.fertileEggs, 0),
    };
  }

  const recent = await statsFor(recentStart, now);
  const prior = await statsFor(priorStart, priorEnd);

  if (!recent && !prior) {
    return { message: 'No detections found in either period.', recent, prior };
  }
  if (!recent || !prior) {
    return {
      message: 'Insufficient data — only one of the two periods has detections.',
      recentPeriod: recent ? { label: `last ${p1} days`, ...recent } : null,
      priorPeriod: prior ? { label: `${p2} days before that`, ...prior } : null,
    };
  }

  const changePoints = round((recent.avgFertilityRate - prior.avgFertilityRate) * 100, 2);
  let shift = 'stable';
  if (changePoints > 2) shift = 'improving';
  else if (changePoints < -2) shift = 'declining';

  return {
    recentPeriod: { label: `last ${p1} days`, ...recent },
    priorPeriod: { label: `${p2} days before that`, ...prior },
    changeInAveragePoints: changePoints,
    direction: shift,
  };
}

module.exports = {
  getRecentReports,
  getFertilityTrend,
  getBatchPerformance,
  compareTimePeriods,
};
