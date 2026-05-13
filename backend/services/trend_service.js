'use strict';

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

// Linear regression slope over an array of values (x = index, y = value)
function calcSlope(values) {
  const n = values.length;
  if (n < 2) return 0;
  const sumX = (n * (n - 1)) / 2;
  const sumX2 = (n * (n - 1) * (2 * n - 1)) / 6;
  const sumY = values.reduce((a, b) => a + b, 0);
  const sumXY = values.reduce((sum, y, i) => sum + i * y, 0);
  return (n * sumXY - sumX * sumY) / (n * sumX2 - sumX * sumX);
}

async function callGemini(prompt) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('Missing GEMINI_API_KEY in environment');

  const response = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig: {
        maxOutputTokens: 400,
        temperature: 0.3,
        // Disable Gemini 2.5 Flash's "thinking" — it silently eats tokens from
        // maxOutputTokens, causing the trend summary to render mid-sentence
        // (e.g. "Poultry fertility has shown a"). Direct prose only.
        thinkingConfig: { thinkingBudget: 0 },
      },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Gemini ${response.status}: ${body}`);
  }

  const data = await response.json();
  const candidate = data.candidates[0];
  const finishReason = candidate.finishReason;
  if (finishReason && finishReason !== 'STOP') {
    console.warn(`[TREND] WARNING: finishReason=${finishReason} — response may be truncated`);
  }
  return candidate.content.parts[0].text.trim();
}

// Generates a trend document from an array of daily_stats documents.
// dailyStats must be sorted oldest first (ascending by date).
async function generateTrendFromDailyStats(userId, dailyStats, db) {
  const windowDays = dailyStats.length;
  const reportCount = dailyStats.reduce((s, d) => s + d.detectionCount, 0);

  let trendDoc = {
    userId,
    generatedAt: new Date(),
    windowDays,
    reportCount,
    averageFertilityRate: 0,
    trend: 'stable',
    trendStrength: 'insufficient_data',
    highestRate: 0,
    lowestRate: 0,
    firstRate: 0,
    lastRate: 0,
    agentSummary:
      'Not enough daily data to analyze trends yet. ' +
      'Run detections on at least 2 separate days to see trend analysis.',
  };

  if (windowDays >= 2) {
    const dailyRates = dailyStats.map((d) => d.averageFertilityRate);
    const avg = dailyRates.reduce((a, b) => a + b, 0) / dailyRates.length;
    const highest = Math.max(...dailyStats.map((d) => d.highestRate));
    const lowest = Math.min(...dailyStats.map((d) => d.lowestRate));
    const slope = calcSlope(dailyRates);

    let direction = 'stable';
    if (slope > 0.02) direction = 'improving';
    else if (slope < -0.02) direction = 'declining';

    const absSlope = Math.abs(slope);
    let strength = 'slight';
    if (absSlope > 0.08) strength = 'strong';
    else if (absSlope > 0.04) strength = 'moderate';

    const ratesStr = dailyStats
      .map((d) => `${d.date}: ${(d.averageFertilityRate * 100).toFixed(1)}% (${d.detectionCount} scans)`)
      .join(', ');

    const prompt =
      `You are an agricultural data analyst specializing in poultry farming.\n\n` +
      `Daily fertility data for this farmer (daily averages, oldest to newest):\n` +
      `- Time window: ${windowDays} days with data\n` +
      `- Total detections across all days: ${reportCount}\n` +
      `- Daily averages: ${ratesStr}\n` +
      `- Overall average: ${(avg * 100).toFixed(1)}%\n` +
      `- Highest single-day average: ${(highest * 100).toFixed(1)}%\n` +
      `- Lowest single-day average: ${(lowest * 100).toFixed(1)}%\n` +
      `- Trend direction: ${direction}\n` +
      `- Trend strength: ${strength}\n\n` +
      `Write a 2-3 sentence plain-text summary of this daily trend. Reference specific ` +
      `numbers and dates. Mention the most likely agricultural cause if the trend is declining. ` +
      `Do not use markdown, bullet points, or LaTeX. Under 120 words.`;

    let agentSummary;
    try {
      agentSummary = await callGemini(prompt);
    } catch (err) {
      console.error(`[TREND] Gemini failed — userId: ${userId}: ${err.message}`);
      agentSummary =
        `Your daily fertility trend over the last ${windowDays} days shows an average of ` +
        `${(avg * 100).toFixed(1)}% across ${reportCount} total detections.`;
    }

    trendDoc = {
      ...trendDoc,
      averageFertilityRate: avg,
      trend: direction,
      trendStrength: strength,
      highestRate: highest,
      lowestRate: lowest,
      firstRate: dailyRates[0],
      lastRate: dailyRates[dailyRates.length - 1],
      agentSummary,
    };
  }

  const result = await db.collection('trends').insertOne(trendDoc);
  console.log(
    `[TREND] Generated from daily_stats — userId: ${userId}, days: ${windowDays}, ` +
    `direction: ${trendDoc.trend}, id: ${result.insertedId}`,
  );
  return { ...trendDoc, _id: result.insertedId };
}

module.exports = { generateTrendFromDailyStats };
