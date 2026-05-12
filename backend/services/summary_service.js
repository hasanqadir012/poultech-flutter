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
      // Bumped from 500 → 1000 to accommodate the richer 9-12 sentence review
      generationConfig: { maxOutputTokens: 1000, temperature: 0.4 },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Gemini ${response.status}: ${body}`);
  }

  const data = await response.json();
  return data.candidates[0].content.parts[0].text.trim();
}

// Group reports by batch label and compute per-batch fertility averages.
// Returns array sorted by avg fertility descending. Used both for the prompt
// (so Gemini can write batch-level analysis) and the fallback prose.
function computeBatchBreakdown(reports) {
  const byLabel = new Map();
  for (const r of reports) {
    const label = r.batchLabel || 'Unlabeled';
    if (!byLabel.has(label)) {
      byLabel.set(label, { count: 0, sumRate: 0, eggs: 0, fertile: 0 });
    }
    const b = byLabel.get(label);
    b.count += 1;
    b.sumRate += r.fertilityRate;
    b.eggs += r.totalEggs;
    b.fertile += r.fertileEggs;
  }
  return Array.from(byLabel.entries())
    .map(([label, b]) => ({
      label,
      count: b.count,
      avgRate: b.sumRate / b.count,
      eggs: b.eggs,
      fertile: b.fertile,
    }))
    .sort((a, b) => b.avgRate - a.avgRate);
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

  // Per-batch breakdown — enables Gemini to write batch-level analysis
  const batchBreakdown = computeBatchBreakdown(reports);
  const batchBreakdownStr = batchBreakdown
    .map((b) =>
      `  • ${b.label}: ${b.count} detection${b.count > 1 ? 's' : ''}, ` +
      `${b.eggs} eggs analyzed, avg ${(b.avgRate * 100).toFixed(1)}% fertility`,
    )
    .join('\n');

  const prompt =
    `You are an agricultural performance analyst writing a detailed weekly report for a poultry hatchery manager in Pakistan.\n\n` +
    `Weekly detection data (${weekStartFmt} to ${weekEndFmt}):\n` +
    `- Total detections run: ${reportCount}\n` +
    `- Total eggs analyzed: ${totalEggsAnalyzed}\n` +
    `- Fertile eggs: ${totalFertileEggs}\n` +
    `- Infertile eggs: ${totalInfertileEggs}\n` +
    `- Average fertility rate: ${avgPct}%\n` +
    `- Best single detection: ${bestLabel}\n` +
    `- Worst single detection: ${worstLabel}\n` +
    (batchesNote ? `${batchesNote}\n` : '') +
    `\nPer-batch breakdown (sorted best to worst):\n${batchBreakdownStr}\n\n` +
    `Write a comprehensive 9-12 sentence weekly performance review covering ALL of the following in order:\n` +
    `1. Overall activity volume — how many detections were run and total eggs processed.\n` +
    `2. Fertility result — exact fertile (${totalFertileEggs}) vs infertile (${totalInfertileEggs}) counts and the ${avgPct}% average. State clearly whether this is healthy (above 65%), borderline (50-65%), or poor (below 50%).\n` +
    `3. Best vs worst single detection — name the batch labels and give the exact percentages.\n` +
    `4. BATCH COMPARISON — using the per-batch breakdown above, explicitly name which batch performed best on average and which worst, with their averages. Comment on what the gap between top and bottom batch suggests (consistent breeding conditions vs. uneven management).\n` +
    `5. Consistency assessment — comment on the spread between the highest (${highPct}%) and lowest (${lowPct}%) detection.\n` +
    `6. Operational context — single vs multiple batches active; what that means for trust in the average.\n` +
    `7. Recommendation — one specific, practical action the farmer should take next week based on the worst-performing batch or the trend, naming the batch if relevant.\n\n` +
    `Requirements: Write 9-12 sentences in plain conversational prose. No bullet points, no markdown, no headers. ` +
    `Reference exact numbers and batch labels throughout. Be direct and professional. Under 350 words.`;

  let agentSummary;
  try {
    agentSummary = await callGemini(prompt);
  } catch (err) {
    console.error(`[SUMMARY] Gemini failed — userId: ${userId}: ${err.message}`);
    // Richer data-driven fallback — references the per-batch breakdown so the
    // user still gets batch-level commentary even when Gemini is unavailable.
    const healthBand = parseFloat(avgPct) >= 65
      ? 'within a healthy range for commercial hatchery operations'
      : parseFloat(avgPct) >= 50
        ? 'in the borderline range and warrants close monitoring'
        : 'below the healthy threshold of 65% and requires immediate attention';
    let batchSentences = '';
    if (batchBreakdown.length > 1) {
      const top = batchBreakdown[0];
      const bottom = batchBreakdown[batchBreakdown.length - 1];
      const gap = ((top.avgRate - bottom.avgRate) * 100).toFixed(0);
      batchSentences =
        `Looking batch-by-batch, ${top.label} led with a ${(top.avgRate * 100).toFixed(1)}% average across ${top.count} detection${top.count > 1 ? 's' : ''}, ` +
        `while ${bottom.label} trailed at ${(bottom.avgRate * 100).toFixed(1)}% over ${bottom.count} detection${bottom.count > 1 ? 's' : ''}. ` +
        `That ${gap}-point gap between your top and bottom batch suggests management or environmental conditions were not uniform this week. `;
    } else if (batchBreakdown.length === 1) {
      const only = batchBreakdown[0];
      batchSentences = `All detections came from ${only.label}, which averaged ${(only.avgRate * 100).toFixed(1)}% fertility across ${only.count} run${only.count > 1 ? 's' : ''}. `;
    }
    agentSummary =
      `This week you ran ${reportCount} detection${reportCount === 1 ? '' : 's'} and analyzed ${totalEggsAnalyzed} eggs in total. ` +
      `Of those, ${totalFertileEggs} were classified as fertile and ${totalInfertileEggs} as infertile, ` +
      `giving an average fertility rate of ${avgPct}%, which is ${healthBand}. ` +
      `Your best single detection this week achieved ${bestLabel}, while the lowest result was ${worstLabel}. ` +
      batchSentences +
      `${batchesActive > 1 ? `You had ${batchesActive} active batches during this period, so the average reflects a mix of conditions.` : 'All detections were part of a single active batch, so the average reflects consistent conditions.'} ` +
      `For next week, focus on identifying the cause of below-average results — particularly in any underperforming batch — and maintain your current detection frequency to support reliable trend analysis.`;
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
