'use strict';

module.exports = {
  // Days of daily_stats fed into trend calculation (Gemini sees this many daily averages)
  TREND_DAILY_STATS_WINDOW: 14,

  // Individual reports (newest first) sent to Gemini for recommendations context
  RECS_RECENT_REPORTS: 10,

  // Max days the /daily-stats chart endpoint will serve (hard ceiling for chart window)
  DAILY_STATS_CHART_MAX: 30,
};
