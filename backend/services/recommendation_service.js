'use strict';

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

// Call Gemini with optional JSON-only mode. JSON mode forces guaranteed valid
// JSON output — avoids parse failures when the model wraps responses in prose
// or markdown fences.
async function callGemini(prompt, { jsonMode = false } = {}) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('Missing GEMINI_API_KEY in environment');

  const generationConfig = {
    maxOutputTokens: 1200,
    temperature: 0.45,
    // Disable Gemini 2.5 Flash's internal "thinking" — it silently eats
    // tokens from maxOutputTokens, leaving the JSON truncated mid-object
    // (which then fails JSON.parse and forces the fallback).
    thinkingConfig: { thinkingBudget: 0 },
  };
  if (jsonMode) generationConfig.responseMimeType = 'application/json';

  const response = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({
      contents: [{ role: 'user', parts: [{ text: prompt }] }],
      generationConfig,
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
    console.warn(`[RECOMMEND] WARNING: finishReason=${finishReason} — response may be truncated`);
  }
  return candidate.content.parts[0].text.trim();
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

// Data-driven fallback — used only when Gemini fails entirely.
// References the user's actual numbers and trend direction so the user still
// sees content tied to their data (not generic placeholders).
function buildDataDrivenFallback(trend) {
  const avg = trend.averageFertilityRate;
  const avgPct = (avg * 100).toFixed(1);
  const lowPct = (trend.lowestRate * 100).toFixed(1);
  const highPct = (trend.highestRate * 100).toFixed(1);
  const spread = (parseFloat(highPct) - parseFloat(lowPct)).toFixed(0);
  const direction = (trend.trend || 'stable').replace(/_/g, ' ');
  const items = [];

  // Primary recommendation — driven by the current average fertility rate
  if (avg < 0.5) {
    items.push({
      priority: 1,
      category: 'rooster_health',
      title: 'Address Low Fertility Rate Urgently',
      action: `Your ${trend.windowDays}-day average is ${avgPct}%, below the 50% healthy threshold. Inspect rooster health, age, and breeding capability this week.`,
      reason: `With detections ranging from ${lowPct}% to ${highPct}%, the most likely culprits are aging roosters, poor protein nutrition, or hens stressed by aggressive males.`,
    });
  } else if (avg < 0.65) {
    items.push({
      priority: 1,
      category: 'flock_management',
      title: 'Lift Fertility Out of Borderline Range',
      action: `Your ${trend.windowDays}-day average of ${avgPct}% sits in the borderline 50-65% range. Audit your rooster-to-hen ratio (1:8–1:12 for broilers) and feed protein levels.`,
      reason: `A ${spread}-point spread between best (${highPct}%) and worst (${lowPct}%) detection signals inconsistent breeding conditions across the flock.`,
    });
  } else {
    items.push({
      priority: 1,
      category: 'monitoring',
      title: 'Maintain Strong Fertility Performance',
      action: `Your ${avgPct}% average is healthy. Keep current management practices and continue running daily detections to catch drift early.`,
      reason: `With a ${highPct}% peak and ${lowPct}% floor over ${trend.windowDays} days, your operation is performing in the healthy range — preserve what's working.`,
    });
  }

  // Secondary recommendation — driven by trend direction
  if (trend.trend === 'declining' || trend.trend === 'strong_decline') {
    items.push({
      priority: 2,
      category: 'incubator',
      title: 'Investigate the Declining Trend',
      action: `Your fertility shows a ${direction} direction. Review this week's incubator temperature, humidity, and egg-turning logs for any anomalies.`,
      reason: 'Declining trends often trace to environmental drift rather than flock issues — catching it early prevents extended losses.',
    });
  } else if (trend.trend === 'improving' || trend.trend === 'strong_improvement') {
    items.push({
      priority: 2,
      category: 'general',
      title: 'Document What Is Working',
      action: `Your fertility is ${direction}. Document the recent changes — feeding schedule, ratios, or conditions — so the gains are repeatable.`,
      reason: 'Identifying the cause of improvement turns one-off gains into permanent practice and protects against regression.',
    });
  } else {
    items.push({
      priority: 2,
      category: 'flock_management',
      title: 'Reduce Variation Between Detections',
      action: `Detections range from ${lowPct}% to ${highPct}% — a ${spread}-point spread. Standardize lighting, ventilation, and feed timing across batches.`,
      reason: 'Consistency matters as much as the average — wide variation means some batches receive better conditions than others.',
    });
  }

  return items;
}

// Extract a JSON array from a string even if surrounded by prose/markdown
function extractJsonArray(raw) {
  const cleaned = raw.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();
  // Try direct parse first (works when jsonMode=true)
  try { return JSON.parse(cleaned); } catch (_) { /* fall through */ }
  // Otherwise, find first [ and last ] and parse the slice
  const start = cleaned.indexOf('[');
  const end = cleaned.lastIndexOf(']');
  if (start !== -1 && end !== -1 && end > start) {
    return JSON.parse(cleaned.slice(start, end + 1));
  }
  throw new Error('No JSON array found in response');
}

async function generateRecommendations(userId, trend, recentReports, db) {
  const n = recentReports.length;
  const reportsStr =
    n > 0 ? formatReportsForPrompt(recentReports) : 'No recent detections available.';
  const trendSummary = buildTrendSummary(trend);
  const avgPct = (trend.averageFertilityRate * 100).toFixed(1);
  const lowPct = (trend.lowestRate * 100).toFixed(1);
  const highPct = (trend.highestRate * 100).toFixed(1);
  const sampleBatchLabel =
    (recentReports[0] && recentReports[0].batchLabel) || 'Batch A';

  const prompt =
    `You are an expert poultry farming advisor writing for a Pakistani broiler hatchery.\n\n` +
    `This farmer's trend snapshot:\n${trendSummary}\n\n` +
    `Their last ${n} detection results:\n${reportsStr}\n\n` +
    `Generate exactly 2 to 4 specific, actionable recommendations as a JSON array.\n\n` +
    `Strict requirements:\n` +
    `1. Every "action" must be a concrete step the farmer can take this week (not generic advice).\n` +
    `2. Every "reason" MUST reference at least one specific number from their data ` +
    `(e.g. the ${avgPct}% average, the ${lowPct}% low, the ${highPct}% high, ` +
    `specific batch names like ${sampleBatchLabel}, or the trend direction "${trend.trend}").\n` +
    `3. Tailor advice to their actual situation — if rate is high, talk about maintaining; ` +
    `if low, talk about urgent investigation; if declining, talk about cause-finding.\n` +
    `4. Vary the categories across the recommendations.\n\n` +
    `JSON schema (return EXACTLY this shape):\n` +
    `[\n` +
    `  {\n` +
    `    "priority": 1,\n` +
    `    "category": "rooster_health",\n` +
    `    "title": "Title under 60 chars",\n` +
    `    "action": "Specific action with concrete steps. 1-2 sentences.",\n` +
    `    "reason": "Why, referencing their actual numbers or batch names. 1-2 sentences."\n` +
    `  }\n` +
    `]\n\n` +
    `Categories: rooster_health, flock_management, incubator, egg_handling, monitoring, general\n` +
    `Priority 1 = most urgent.`;

  let items;
  try {
    // Use JSON mode — Gemini guarantees valid JSON output, eliminating parse failures
    const raw = await callGemini(prompt, { jsonMode: true });
    const parsed = extractJsonArray(raw);
    if (!Array.isArray(parsed) || parsed.length === 0) {
      throw new Error('Empty or non-array response');
    }
    items = parsed.slice(0, 4).map((item, idx) => ({
      priority: typeof item.priority === 'number' ? item.priority : idx + 1,
      category: typeof item.category === 'string' ? item.category : 'general',
      title: typeof item.title === 'string' ? item.title.slice(0, 80) : 'Review farming conditions',
      action: typeof item.action === 'string' ? item.action : '',
      reason: typeof item.reason === 'string' ? item.reason : '',
    }));
    if (items.length < 2) {
      // Pad with data-driven fallback rather than generic defaults
      items = [...items, ...buildDataDrivenFallback(trend)].slice(0, 2);
    }
    console.log(`[RECOMMEND] Gemini OK — userId: ${userId}, items: ${items.length}`);
  } catch (err) {
    console.error(`[RECOMMEND] Gemini failed — userId: ${userId}: ${err.message}. Using data-driven fallback.`);
    items = buildDataDrivenFallback(trend);
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
