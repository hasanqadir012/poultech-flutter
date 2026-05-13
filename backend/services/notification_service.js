'use strict';

const admin = require('firebase-admin');

/**
 * Send a single FCM push notification to a user.
 *
 * Reads the user's stored FCM token from `user_settings` and dispatches via
 * Firebase Admin SDK. Silently no-ops if the user has no token. If Firebase
 * reports the token is invalid/unregistered, clears it from the DB so we
 * don't keep retrying a dead token.
 *
 * @param {string} userId
 * @param {object} db - MongoDB db handle
 * @param {object} payload - { title, body, data }
 *   - title: notification title (string)
 *   - body: notification body (string)
 *   - data: extra key-value pairs (all values must be strings) used by the
 *     Flutter app to deep-link on tap. We use { type, screen } convention.
 */
async function sendNotification(userId, db, { title, body, data = {} }) {
  const user = await db.collection('user_settings').findOne({ _id: userId });
  if (!user || !user.fcmToken) {
    console.log(`[NOTIFY] No FCM token for userId: ${userId} — skipping "${title}"`);
    return false;
  }

  // FCM requires all data values to be strings
  const stringifiedData = {};
  for (const [k, v] of Object.entries(data)) {
    stringifiedData[k] = String(v);
  }

  try {
    const messageId = await admin.messaging().send({
      token: user.fcmToken,
      notification: { title, body },
      data: stringifiedData,
      android: {
        priority: 'high',
        notification: {
          channelId: 'poultech_default',
          // Wakes the screen and plays default sound on Android
          defaultSound: true,
        },
      },
    });
    console.log(`[NOTIFY] Sent "${title}" → userId: ${userId}, messageId: ${messageId}`);
    return true;
  } catch (err) {
    console.error(`[NOTIFY] Failed for userId: ${userId} — "${title}": ${err.message}`);
    // Invalid token → clear it so future calls don't retry the same dead token
    if (
      err.code === 'messaging/registration-token-not-registered' ||
      err.code === 'messaging/invalid-registration-token'
    ) {
      await db
        .collection('user_settings')
        .updateOne({ _id: userId }, { $unset: { fcmToken: '' } });
      console.log(`[NOTIFY] Cleared invalid token for userId: ${userId}`);
    }
    return false;
  }
}

module.exports = { sendNotification };
