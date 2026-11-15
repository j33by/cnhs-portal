const admin = require('firebase-admin');
let fcm = null;
if (process.env.FCM_SERVICE_ACCOUNT_JSON) {
  admin.initializeApp({ credential: admin.credential.cert(JSON.parse(process.env.FCM_SERVICE_ACCOUNT_JSON)) });
  fcm = admin.messaging();
}
// Saves an in-app notification (delivered realtime by Supabase) and sends a phone push when a token exists.
async function notify(sb, userIds, { title, body, kind, data }) {
  const ids = [...new Set(userIds.filter(Boolean))]; if (!ids.length) return;
  await sb.from('notifications').insert(ids.map(user_id => ({ user_id, title, body, kind, data })));
  if (!fcm) return;
  const { data: ps } = await sb.from('profiles').select('fcm_token').in('id', ids).not('fcm_token', 'is', null);
  const tokens = (ps || []).map(p => p.fcm_token);
  if (tokens.length) await fcm.sendEachForMulticast({ tokens, notification: { title, body }, data: { kind: kind || '' },
    android: { priority: 'high', notification: { channelId: 'attendance' } } }).catch(() => {});
}
module.exports = { notify };
