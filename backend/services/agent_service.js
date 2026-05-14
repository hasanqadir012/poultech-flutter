'use strict';

// Agentic analysis service — runs a ReAct loop with Gemini function calling.
// Gemini decides which tools to call, in what order, and when to stop.
// Final output is a structured diagnosis with evidence and recommendations.

const {
  getRecentReports,
  getFertilityTrend,
  getBatchPerformance,
  compareTimePeriods,
} = require('./agent_tools');
const { getPktNow, getPktDateString } = require('./daily_stats_service');
const { sendNotification } = require('./notification_service');

const GEMINI_URL =
  'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent';

const MAX_ITERATIONS = 4;

// Tool schema declared to Gemini. Each entry's `name` maps to a function
// in agent_tools.js via the executeTool dispatcher below.
const TOOL_DECLARATIONS = [{
  functionDeclarations: [
    {
      name: 'get_recent_reports',
      description:
        'Fetches the farmer\'s most recent individual detection reports. ' +
        'Use this to inspect the latest scans, see batch labels, and spot raw values.',
      parameters: {
        type: 'object',
        properties: {
          limit: {
            type: 'number',
            description: 'How many reports to fetch (1-50, default 10).',
          },
        },
      },
    },
    {
      name: 'get_fertility_trend',
      description:
        'Computes the fertility trend (direction, slope, daily averages) over a window of N days. ' +
        'Use this to see the macro picture. Try 7 for short-term, 14 for medium, 30 for long-term.',
      parameters: {
        type: 'object',
        properties: {
          days: {
            type: 'number',
            description: 'Number of days to analyze (1-60). 7=short, 14=medium, 30=long.',
          },
        },
        required: ['days'],
      },
    },
    {
      name: 'get_batch_performance',
      description:
        'Breaks down fertility by batch. Omit batchLabel to compare ALL batches side-by-side. ' +
        'Pass a specific batchLabel to deep-dive that one batch (its avg, range, dates).',
      parameters: {
        type: 'object',
        properties: {
          batchLabel: {
            type: 'string',
            description: 'Optional. The specific batch to investigate. Omit to compare all batches.',
          },
        },
      },
    },
    {
      name: 'compare_time_periods',
      description:
        'Compares two consecutive time windows ending now. ' +
        'e.g. period1Days=7, period2Days=7 → last week vs the week before. ' +
        'Use this when you suspect a recent shift in performance.',
      parameters: {
        type: 'object',
        properties: {
          period1Days: { type: 'number', description: 'Length of the recent period in days.' },
          period2Days: { type: 'number', description: 'Length of the prior period in days.' },
        },
        required: ['period1Days', 'period2Days'],
      },
    },
  ],
}];

const SYSTEM_INSTRUCTION =
  `You are an expert poultry hatchery analyst agent working with a Pakistani broiler farmer.\n` +
  `Your job: investigate this farmer's egg-fertility data, identify the root cause of any issues, ` +
  `and produce a specific evidence-based diagnosis.\n\n` +
  `INVESTIGATION RULES:\n` +
  `1. Always START by gathering context: call get_fertility_trend (try 14 days) and get_recent_reports (5-10).\n` +
  `2. If the trend is declining or unstable, DIG DEEPER — call get_batch_performance to see if it's batch-specific, ` +
  `or compare_time_periods to confirm the timing of the shift.\n` +
  `3. If the trend looks healthy, you can stop after 1-2 tool calls — no need to over-investigate.\n` +
  `4. NEVER produce generic advice. Every recommendation must cite a SPECIFIC number, batch name, or date from the tools.\n` +
  `5. You have at most 4 tool calls. Use them wisely.\n\n` +
  `FINAL OUTPUT:\n` +
  `When you have enough evidence, stop calling tools and return a JSON object with this EXACT schema:\n` +
  `{\n` +
  `  "diagnosis": "One-line root cause assessment.",\n` +
  `  "severity": "critical" | "high" | "moderate" | "low" | "healthy",\n` +
  `  "evidence": ["Specific finding 1 (with numbers).", "Specific finding 2.", ...],\n` +
  `  "trendNarrative": "2-3 sentence plain prose summary of the trend, referencing exact averages and dates.",\n` +
  `  "recommendations": [\n` +
  `    {\n` +
  `      "title": "Short action title under 60 chars",\n` +
  `      "body": "1-2 sentences explaining the action and citing the evidence number that motivates it.",\n` +
  `      "priority": 1\n` +
  `    }\n` +
  `  ]\n` +
  `}\n` +
  `Return 2-4 recommendations. priority: 1 = most urgent.\n` +
  `Severity levels:\n` +
  `- critical: avg <40% OR sudden drop >20 points\n` +
  `- high: avg 40-55% OR declining trend with strength=strong\n` +
  `- moderate: avg 55-65% OR declining slight/moderate\n` +
  `- low: avg 65-75% with any variability concern\n` +
  `- healthy: avg ≥75% AND stable or improving`;

// Dispatch a tool call from Gemini to its implementation.
async function executeTool(name, args, userId, db) {
  console.log(`[AGENT] → ${name}(${JSON.stringify(args || {})})`);
  try {
    switch (name) {
      case 'get_recent_reports':
        return await getRecentReports(userId, args?.limit, db);
      case 'get_fertility_trend':
        return await getFertilityTrend(userId, args?.days, db);
      case 'get_batch_performance':
        return await getBatchPerformance(userId, args?.batchLabel, db);
      case 'compare_time_periods':
        return await compareTimePeriods(userId, args?.period1Days, args?.period2Days, db);
      default:
        return { error: `Unknown tool: ${name}` };
    }
  } catch (err) {
    console.error(`[AGENT] Tool ${name} threw:`, err.message);
    return { error: err.message };
  }
}

// Gemini call. Two modes:
// - tool reasoning: tools enabled, thinking dynamic, generous output budget
// - final answer: tools disabled, thinking off (no token competition), JSON mime
async function callGemini(contents, { withTools }) {
  const apiKey = process.env.GEMINI_API_KEY;
  if (!apiKey) throw new Error('Missing GEMINI_API_KEY in environment');

  const generationConfig = withTools
    ? {
        maxOutputTokens: 4000,
        temperature: 0.3,
        // thinkingConfig omitted → dynamic thinking (helps tool-selection reasoning).
        // Output is small (just a functionCall), so thinking can't truncate it.
      }
    : {
        maxOutputTokens: 2500,
        temperature: 0.3,
        // Final-answer mode: kill thinking so it can't eat the JSON prose budget.
        thinkingConfig: { thinkingBudget: 0 },
        responseMimeType: 'application/json',
      };

  const body = {
    contents,
    systemInstruction: { parts: [{ text: SYSTEM_INSTRUCTION }] },
    generationConfig,
  };
  if (withTools) body.tools = TOOL_DECLARATIONS;

  const response = await fetch(`${GEMINI_URL}?key=${apiKey}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  });

  if (!response.ok) {
    const text = await response.text();
    throw new Error(`Gemini ${response.status}: ${text}`);
  }

  return await response.json();
}

// Robustly extract a JSON object from a text response (handles stray prose/fences).
function parseFinalJson(text) {
  const cleaned = text.replace(/^```(?:json)?\s*/i, '').replace(/\s*```\s*$/i, '').trim();
  try {
    return JSON.parse(cleaned);
  } catch (_) {
    const start = cleaned.indexOf('{');
    const end = cleaned.lastIndexOf('}');
    if (start !== -1 && end > start) {
      return JSON.parse(cleaned.slice(start, end + 1));
    }
    throw new Error('No JSON object found in final response');
  }
}

// Normalize the agent's final JSON into the shape we store + return.
function normalizeFinal(raw) {
  const validSeverity = ['critical', 'high', 'moderate', 'low', 'healthy'];
  const recs = Array.isArray(raw.recommendations) ? raw.recommendations : [];
  return {
    diagnosis: typeof raw.diagnosis === 'string' ? raw.diagnosis : 'No diagnosis produced.',
    severity: validSeverity.includes(raw.severity) ? raw.severity : 'moderate',
    evidence: Array.isArray(raw.evidence) ? raw.evidence.filter((e) => typeof e === 'string') : [],
    trendNarrative: typeof raw.trendNarrative === 'string' ? raw.trendNarrative : '',
    recommendations: recs.slice(0, 4).map((r, i) => ({
      title: typeof r.title === 'string' ? r.title.slice(0, 80) : `Recommendation ${i + 1}`,
      body: typeof r.body === 'string' ? r.body : '',
      priority: typeof r.priority === 'number' ? r.priority : i + 1,
    })),
  };
}

// ─────────────────────────────────────────────────────────────────────────────
// Main entry — runs the ReAct loop and returns the final structured analysis.
// Does NOT save to MongoDB. The caller (route or daily_analysis_service) saves.
// ─────────────────────────────────────────────────────────────────────────────
async function runAgentAnalysis(userId, db) {
  const startedAt = Date.now();
  console.log(`[AGENT] Starting — userId: ${userId}`);

  const todayStr = new Date().toISOString().slice(0, 10);
  const contents = [{
    role: 'user',
    parts: [{
      text:
        `Analyze the current hatchery situation for this farmer. ` +
        `Today is ${todayStr}. Investigate using the tools available, then produce ` +
        `your final diagnosis with evidence and recommendations.`,
    }],
  }];

  const toolsCalled = [];
  let iteration = 0;
  let finalText = null;

  // Loop with tools enabled
  while (iteration < MAX_ITERATIONS) {
    iteration++;

    const response = await callGemini(contents, { withTools: true });
    const candidate = response.candidates?.[0];
    if (!candidate) throw new Error('No candidate in Gemini response');

    const parts = candidate.content?.parts || [];
    const toolCallPart = parts.find((p) => p.functionCall);

    if (!toolCallPart) {
      const textPart = parts.find((p) => p.text);
      finalText = textPart?.text || null;
      console.log(`[AGENT] Model produced final text at iteration ${iteration}`);
      break;
    }

    const toolName = toolCallPart.functionCall.name;
    const toolArgs = toolCallPart.functionCall.args || {};
    toolsCalled.push({ name: toolName, args: toolArgs, iteration });

    const toolResult = await executeTool(toolName, toolArgs, userId, db);

    // Append model's tool call AND our tool response to the conversation.
    contents.push({
      role: 'model',
      parts: [{ functionCall: { name: toolName, args: toolArgs } }],
    });
    contents.push({
      role: 'user',
      parts: [{ functionResponse: { name: toolName, response: toolResult } }],
    });
  }

  // If we exhausted iterations without a final text, force a closing call
  // with tools disabled + JSON mode. This guarantees we get a final answer.
  if (!finalText) {
    console.log('[AGENT] Iteration cap reached — requesting final answer with no tools');
    contents.push({
      role: 'user',
      parts: [{
        text:
          'You have gathered enough evidence. Stop calling tools and produce your final ' +
          'JSON response now, matching the schema in the system instruction.',
      }],
    });

    const closing = await callGemini(contents, { withTools: false });
    const candidate = closing.candidates?.[0];
    const textPart = candidate?.content?.parts?.find((p) => p.text);
    if (!textPart?.text) throw new Error('Agent produced no final text after closing call');
    finalText = textPart.text;
  }

  let parsed;
  try {
    parsed = parseFinalJson(finalText);
  } catch (err) {
    console.error(`[AGENT] Failed to parse final JSON — userId: ${userId}: ${err.message}`);
    console.error(`[AGENT] Raw final text was: ${finalText.slice(0, 500)}`);
    throw new Error(`Agent final output was not valid JSON: ${err.message}`);
  }

  const normalized = normalizeFinal(parsed);
  const elapsedMs = Date.now() - startedAt;

  console.log(
    `[AGENT] Complete — userId: ${userId}, ` +
    `iterations: ${iteration}, tools: ${toolsCalled.length}, ` +
    `severity: ${normalized.severity}, elapsed: ${elapsedMs}ms`,
  );

  return {
    ...normalized,
    toolsCalled,
    iterations: iteration,
    elapsedMs,
  };
}

// Map severity to a short notification title.
function severityTitle(severity) {
  switch (severity) {
    case 'critical': return 'AI Analyst — Critical issue detected';
    case 'high':     return 'AI Analyst — Action needed';
    case 'moderate': return 'Today\'s AI Analysis';
    case 'low':      return 'Today\'s AI Analysis';
    case 'healthy':  return 'Today\'s AI Analysis — Healthy';
    default:         return 'Today\'s AI Analysis';
  }
}

// Run the agent and persist the result into agent_analyses (upsert keyed by
// {userId, pktDate}). Returns the saved document.
//
// Pass `{ silent: true }` to skip the FCM push (used by force-regenerate so
// the user isn't double-notified when they explicitly re-ran the analysis).
async function runAndSaveAgentAnalysis(userId, db, { silent = false } = {}) {
  const analysis = await runAgentAnalysis(userId, db);
  const pktDate = getPktDateString(getPktNow());

  const doc = {
    userId,
    pktDate,
    generatedAt: new Date(),
    diagnosis: analysis.diagnosis,
    severity: analysis.severity,
    evidence: analysis.evidence,
    trendNarrative: analysis.trendNarrative,
    recommendations: analysis.recommendations,
    toolsCalled: analysis.toolsCalled,
    iterations: analysis.iterations,
    elapsedMs: analysis.elapsedMs,
  };

  await db.collection('agent_analyses').updateOne(
    { userId, pktDate },
    { $set: doc },
    { upsert: true },
  );

  const saved = await db.collection('agent_analyses').findOne({ userId, pktDate });
  console.log(
    `[AGENT] Saved — userId: ${userId}, pktDate: ${pktDate}, ` +
    `severity: ${doc.severity}, recs: ${doc.recommendations.length}`,
  );

  // Fire-and-forget FCM push. Body is the diagnosis (truncated). Tap opens
  // the AgentAnalysisScreen (screen=agent).
  if (!silent) {
    const body = analysis.diagnosis.length > 140
      ? `${analysis.diagnosis.slice(0, 137)}…`
      : analysis.diagnosis;
    sendNotification(userId, db, {
      title: severityTitle(analysis.severity),
      body,
      data: {
        type: 'agent',
        screen: 'agent',
        severity: analysis.severity,
        pktDate,
      },
    }).catch((err) => console.error(`[AGENT] Notification dispatch failed: ${err.message}`));
  }

  return saved;
}

module.exports = { runAgentAnalysis, runAndSaveAgentAnalysis };
