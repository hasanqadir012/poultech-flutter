'use strict';

const admin = require('firebase-admin');

// Send an FCM notification to a user. Reads the user's fcmToken from
// user_settings and delivers via Firebase Cloud Messaging.
//
// Silently no-ops if the user has no registered token (web logins, fresh
// signups before NotificationService.initialize() has run, etc.).
//
// Auto-clears stale tokens: if FCM reports the token is no longer registered
// (uninstall, app data cleared, etc.) we wipe it from user_settings so we
// don't keep retrying.
async function sendNotification(userId, db, { title, body, data = {} } = {}) {
  const settings = await db.collection('user_settings').findOne({ _id: userId });
  if (!settings || !settings.fcmToken) {
    console.log(`[NOTIFY] No FCM token for userId: ${userId} — skipping`);
    return false;
  }

  // FCM data payload values must be strings.
  const stringData = {};
  for (const [k, v] of Object.entries(data)) {
    if (v === null || v === undefined) continue;
    stringData[k] = String(v);
  }

  const message = {
    token: settings.fcmToken,
    notification: { title, body },
    data: stringData,
    android: {
      notification: {
        channelId: 'poultech_default',
        priority: 'high',
      },
    },
  };

  try {
    const id = await admin.messaging().send(message);
    console.log(
      `[NOTIFY] Sent — userId: ${userId}, type: ${stringData.type || 'unknown'}, id: ${id}`,
    );
    return true;
  } catch (err) {
    if (err.code === 'messaging/registration-token-not-registered') {
      console.log(`[NOTIFY] Stale token — clearing. userId: ${userId}`);
      await db.collection('user_settings').updateOne(
        { _id: userId },
        { $unset: { fcmToken: '' } },
      );
    } else {
      console.error(`[NOTIFY] Failed — userId: ${userId}: ${err.message}`);
    }
    return false;
  }
}

module.exports = { sendNotification };
