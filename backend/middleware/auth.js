'use strict';

const admin = require('firebase-admin');

// Initialize Firebase Admin SDK once
if (!admin.apps.length) {
  const credential = process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON
    ? admin.credential.cert(JSON.parse(process.env.GOOGLE_APPLICATION_CREDENTIALS_JSON))
    : admin.credential.applicationDefault();

  admin.initializeApp({
    credential,
    projectId: process.env.FIREBASE_PROJECT_ID,
  });

  console.log(JSON.stringify({
    timestamp: new Date().toISOString(),
    level: 'INFO',
    message: 'Firebase Admin SDK initialized',
    projectId: process.env.FIREBASE_PROJECT_ID,
  }));
}

async function verifyToken(req, res, next) {
  console.log(`[AUTH] Verifying token for ${req.method} ${req.path}`);

  const authHeader = req.headers.authorization;
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    console.warn(`[AUTH] Missing or malformed Authorization header on ${req.path}`);
    return res.status(401).json({ error: 'Unauthorized: no token provided' });
  }

  const token = authHeader.split('Bearer ')[1];

  try {
    const decoded = await admin.auth().verifyIdToken(token);
    req.userId = decoded.uid;
    console.log(`[AUTH] Token valid — userId: ${decoded.uid}`);
    next();
  } catch (err) {
    console.error(`[AUTH] Token invalid — error: ${err.message}`);
    return res.status(401).json({ error: 'Unauthorized: invalid token' });
  }
}

module.exports = verifyToken;
