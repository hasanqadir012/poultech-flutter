'use strict';

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

async function callGemini(prompt) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('Missing GEMINI_API_KEY in environment');

  const response = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: { maxOutputTokens: 500, temperature: 0.35 },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Gemini ${response.status}: ${body}`);
  }

  const data = await response.json();
  return data.candidates[0].content.parts[0].text.trim();
}

function fmtDate(d) {
  const months = ['Jan','Feb','Mar','Apr','May','Jun','Jul','Aug','Sep','Oct','Nov','Dec'];
  return `${months[d.getMonth()]} ${d.getDate()}`;
}

// Generates and saves a weekly summary for the given date range.
// Returns null (no DB write) when the period has zero reports.
async function generateWeeklySummary(userId, weekStart, weekEnd, db) {
  const reports = await db
    .collection('reports')
    .find({ userId, createdAt: { $gte: weekStart, $lte: weekEnd } })
    .sort({ createdAt: 1 })
    .toArray();

  if (reports.length === 0) {
    console.log(`[SUMMARY] No reports in period — userId: ${userId}, skipping`);
    return null;
  }

  const reportCount = reports.length;
  const totalEggsAnalyzed = reports.reduce((s, r) => s + r.totalEggs, 0);
  const totalFertileEggs = reports.reduce((s, r) => s + r.fertileEggs, 0);
  const totalInfertileEggs = reports.reduce((s, r) => s + r.infertileEggs, 0);
  const rates = reports.map((r) => r.fertilityRate);
  const averageFertilityRate = rates.reduce((a, b) => a + b, 0) / rates.length;
  const highestFertilityRate = Math.max(...rates);
  const lowestFertilityRate = Math.min(...rates);

  const bestReport = reports.find((r) => r.fertilityRate === highestFertilityRate);
  const worstReport = reports.find((r) => r.fertilityRate === lowestFertilityRate);
  const bestBatchLabel = bestReport ? (bestReport.batchLabel || null) : null;
  const worstBatchLabel = worstReport ? (worstReport.batchLabel || null) : null;

  // Count distinct batchIds (ignoring null)
  const batchIds = new Set(
    reports.map((r) => r.batchId).filter(Boolean),
  );
  const batchesActive = batchIds.size;

  const weekStartFmt = fmtDate(weekStart);
  const weekEndFmt = fmtDate(weekEnd);
  const avgPct = (averageFertilityRate * 100).toFixed(1);
  const highPct = (highestFertilityRate * 100).toFixed(1);
  const lowPct = (lowestFertilityRate * 100).toFixed(1);

  const bestLabel = bestBatchLabel ? `${highPct}% (${bestBatchLabel})` : `${highPct}%`;
  const worstLabel = worstBatchLabel ? `${lowPct}% (${worstBatchLabel})` : `${lowPct}%`;

  const batchesNote = batchesActive > 0
    ? `- Active batches this week: ${batchesActive}`
    : '';

  const prompt =
    `You are an agricultural performance analyst writing a formal weekly report for a poultry hatchery manager.\n\n` +
    `Weekly detection data (${weekStartFmt} to ${weekEndFmt}):\n` +
    `- Total detections run: ${reportCount}\n` +
    `- Total eggs analyzed: ${totalEggsAnalyzed}\n` +
    `- Fertile eggs: ${totalFertileEggs}\n` +
    `- Infertile eggs: ${totalInfertileEggs}\n` +
    `- Average fertility rate: ${avgPct}%\n` +
    `- Best single detection: ${bestLabel}\n` +
    `- Worst single detection: ${worstLabel}\n` +
    (batchesNote ? `${batchesNote}\n` : '') +
    `\n` +
    `Write a comprehensive weekly performance review covering ALL of the following points in order:\n` +
    `1. Overall volume: how many detections were run and total eggs processed.\n` +
    `2. Fertility results: exact fertile vs infertile counts and the average rate. State clearly whether ${avgPct}% is healthy (above 65%), borderline (50-65%), or poor (below 50%).\n` +
    `3. Performance range: the best and worst single detection results this week, naming the batch if one is provided.\n` +
    `4. Consistency assessment: comment on whether performance was consistent or variable based on the gap between best (${bestLabel}) and worst (${worstLabel}).\n` +
    `5. Operational context: if multiple batches were active, note that. If only one batch, note that.\n` +
    `6. Recommendation: one specific, practical action the farmer should take next week based on this week's results.\n` +
    `\n` +
    `Requirements: Write 6-8 sentences in plain conversational prose. No bullet points, no markdown, no headers. ` +
    `Reference the actual numbers throughout. Be direct and professional. Under 250 words.`;

  let agentSummary;
  try {
    agentSummary = await callGemini(prompt);
  } catch (err) {
    console.error(`[SUMMARY] Gemini failed — userId: ${userId}: ${err.message}`);
    agentSummary =
      `This week you ran ${reportCount} detection${reportCount === 1 ? '' : 's'} and analyzed ${totalEggsAnalyzed} eggs in total. ` +
      `Of those, ${totalFertileEggs} were classified as fertile and ${totalInfertileEggs} as infertile, ` +
      `giving an average fertility rate of ${avgPct}%. ` +
      `${parseFloat(avgPct) >= 65 ? 'This is within a healthy range for commercial hatchery operations.' : parseFloat(avgPct) >= 50 ? 'This is in the borderline range and warrants close monitoring.' : 'This is below the healthy threshold of 65% and requires immediate attention.'} ` +
      `Your best detection this week achieved ${bestLabel}, while the lowest result was ${worstLabel}. ` +
      `${batchesActive > 1 ? `You had ${batchesActive} active batches during this period.` : 'All detections were part of a single active batch.'} ` +
      `For next week, focus on identifying the cause of any below-average results and maintain your current detection frequency to support trend analysis.`;
  }

  const doc = {
    userId,
    weekStart,
    weekEnd,
    generatedAt: new Date(),
    reportCount,
    totalEggsAnalyzed,
    totalFertileEggs,
    totalInfertileEggs,
    averageFertilityRate,
    highestFertilityRate,
    lowestFertilityRate,
    bestBatchLabel,
    worstBatchLabel,
    batchesActive,
    agentSummary,
    isRead: false,
  };

  const result = await db.collection('summaries').insertOne(doc);
  console.log(
    `[SUMMARY] Generated — userId: ${userId}, period: ${weekStartFmt}–${weekEndFmt}, ` +
    `reports: ${reportCount}, id: ${result.insertedId}`,
  );
  return { ...doc, _id: result.insertedId };
}

module.exports = { generateWeeklySummary };
