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
      generationConfig: { maxOutputTokens: 700, temperature: 0.4 },
    }),
  });

  if (!response.ok) {
    const body = await response.text();
    throw new Error(`Gemini ${response.status}: ${body}`);
  }

  const data = await response.json();
  return data.candidates[0].content.parts[0].text.trim();
}

function formatReportsForPrompt(reports) {
  return reports
    .map((r, i) => {
      const date = new Date(r.createdAt).toLocaleDateString('en-US', {
        month: 'short',
        day: 'numeric',
      });
      const rate = (r.fertilityRate * 100).toFixed(1);
      const batch = r.batchLabel ? `, Batch: ${r.batchLabel}` : '';
      return `Report ${i + 1} (${date}): ${r.totalEggs} eggs, ${r.fertileEggs} fertile, ${rate}% fertility${batch}`;
    })
    .join('\n');
}

function buildTrendSummary(trend) {
  return (
    `Trend direction: ${trend.trend}, Strength: ${trend.trendStrength}, ` +
    `Window: ${trend.windowDays} days, Reports in window: ${trend.reportCount}, ` +
    `Average fertility: ${(trend.averageFertilityRate * 100).toFixed(1)}%, ` +
    `Highest: ${(trend.highestRate * 100).toFixed(1)}%, ` +
    `Lowest: ${(trend.lowestRate * 100).toFixed(1)}%`
  );
}

function defaultRecommendations() {
  return [
    {
      priority: 1,
      category: 'monitoring',
      title: 'Establish Regular Detection Schedule',
      action:
        'Run egg fertility detections at least 3 times per week to build a reliable data baseline.',
      reason:
        'Consistent data collection enables accurate trend analysis and early anomaly detection.',
    },
    {
      priority: 2,
      category: 'flock_management',
      title: 'Review Male-to-Female Ratio',
      action:
        'Verify that your rooster-to-hen ratio meets breed standards (typically 1:8 to 1:12 for broilers).',
      reason:
        'Incorrect sex ratios are one of the most common causes of reduced fertility rates.',
    },
  ];
}

async function generateRecommendations(userId, trend, recentReports, db) {
  const n = recentReports.length;
  const reportsStr =
    n > 0 ? formatReportsForPrompt(recentReports) : 'No recent detections available.';
  const trendSummary = buildTrendSummary(trend);

  const prompt =
    `You are an expert poultry farming advisor.\n\n` +
    `This farmer's trend data:\n${trendSummary}\n\n` +
    `Their last ${n} detection results:\n${reportsStr}\n\n` +
    `Generate exactly 2 to 4 specific, actionable recommendations.\n` +
    `Return ONLY a valid JSON array. No prose, no markdown, no code blocks.\n` +
    `Format:\n` +
    `[\n` +
    `  {\n` +
    `    "priority": 1,\n` +
    `    "category": "rooster_health",\n` +
    `    "title": "Short action title under 60 chars",\n` +
    `    "action": "Specific thing to do. One or two sentences.",\n` +
    `    "reason": "Why this is recommended based on their specific data. One or two sentences."\n` +
    `  }\n` +
    `]\n\n` +
    `Categories: rooster_health, flock_management, incubator, egg_handling, monitoring, general\n` +
    `Priority 1 = most urgent. Use their actual numbers in the reason fields.`;

  let items;
  try {
    let raw = await callGemini(prompt);
    // Strip any accidental markdown code fences
    raw = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();
    const parsed = JSON.parse(raw);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error('Empty or non-array response');
    }
    // Clamp to 2-4 items and validate required fields
    items = parsed.slice(0, 4).map((item, idx) => ({
      priority: typeof item.priority === 'number' ? item.priority : idx + 1,
      category: typeof item.category === 'string' ? item.category : 'general',
      title: typeof item.title === 'string' ? item.title.slice(0, 80) : 'Review farming conditions',
      action: typeof item.action === 'string' ? item.action : '',
      reason: typeof item.reason === 'string' ? item.reason : '',
    }));
    // Ensure at least 2 items
    if (items.length < 2) {
      items = [...items, ...defaultRecommendations()].slice(0, 2);
    }
  } catch (err) {
    console.error(`[RECOMMEND] Gemini parse failed — userId: ${userId}: ${err.message}`);
    items = defaultRecommendations();
  }

  const doc = {
    userId,
    trendId: trend._id ? trend._id.toString() : null,
    generatedAt: new Date(),
    isRead: false,
    recommendations: items,
  };

  const result = await db.collection('recommendations').insertOne(doc);
  console.log(
    `[RECOMMEND] Generated — userId: ${userId}, items: ${items.length}, id: ${result.insertedId}`,
  );
  return { ...doc, _id: result.insertedId };
}

module.exports = { generateRecommendations };
