const crypto = require('crypto');

// Room voice messages: one per person per section, max 30 s, gone after 12 hours.
module.exports = function mount(app, { sb, wrap, bad, up }) {
  const FILES_URL = (process.env.SUPABASE_URL || '').replace(/\/$/, '') + '/storage/v1/object/public/room-voice/';
  const TYPES = { m4a: 'audio/mp4', mp4: 'audio/mp4', aac: 'audio/aac', ogg: 'audio/ogg', webm: 'audio/webm', wav: 'audio/wav', mp3: 'audio/mpeg' };
  const MAX_BYTES = 3 * 1024 * 1024, MAX_MS = 30500, MIN_MS = 300;
  const pathOf = url => typeof url === 'string' && url.startsWith(FILES_URL) ? url.slice(FILES_URL.length) : null;

  // may this person use the Room of this section? students: their own section. teachers: adviser or subject teacher of it.
  const access = async (q, sectionId) => {
    const uid = q.user.id, role = q.profile?.role;
    if (!sectionId) throw bad('Section missing.');
    if (role === 'student') {
      const { data: s } = await sb.from('students').select('section_id').eq('id', uid).maybeSingle();
      if (!s || s.section_id !== sectionId) throw bad('This is not your section.', 403);
      return { adviser: false };
    }
    if (role === 'teacher') {
      const { data: sec } = await sb.from('sections').select('adviser_id').eq('id', sectionId).maybeSingle(); if (!sec) throw bad('Section not found', 404);
      const adviser = sec.adviser_id === uid;
      if (!adviser) { const { data: ss } = await sb.from('section_subjects').select('section_id').eq('section_id', sectionId).eq('teacher_id', uid).limit(1); if (!ss?.length) throw bad('You do not teach this section.', 403); }
      return { adviser };
    }
    throw bad('Not allowed.', 403);
  };
  const removeFiles = async urls => { const paths = urls.map(pathOf).filter(Boolean); if (paths.length) await sb.storage.from('room-voice').remove(paths).catch(() => {}); };

  // delete everything that is older than 12 hours (rows + audio files). Also run on a timer from server.js.
  const purge = async () => {
    const { data } = await sb.from('room_voice').select('id,audio_url').lt('expires_at', new Date().toISOString()).limit(200);
    if (!data?.length) return 0;
    await removeFiles(data.map(v => v.audio_url));
    await sb.from('room_voice').delete().in('id', data.map(v => v.id));
    return data.length;
  };
  app.purgeRoomVoice = purge;

  const receive = (q, r, next) => up.any()(q, r, err => err ? r.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ error: err.code === 'LIMIT_FILE_SIZE' ? 'Voice message is too big.' : 'Upload failed.' }) : next());

  // post (or replace) my voice message. multipart: the file; section_id and ms in the query string
  app.post('/api/room/voice', receive, wrap(async (q, r) => {
    const sectionId = String(q.query.section_id || ''), ms = Math.round(+q.query.ms);
    await access(q, sectionId);
    const f = (q.files || [])[0]; if (!f) throw bad('Record a voice message first.');
    if (!(ms >= MIN_MS)) throw bad('That recording is too short.');
    if (ms > MAX_MS) throw bad('Voice messages can be at most 30 seconds.');
    if (f.size > MAX_BYTES) throw bad('Voice message is too big.', 413);
    const name = String(f.originalname || f.fieldname || 'voice.m4a'), ext = (name.split('.').pop() || '').toLowerCase(), type = TYPES[ext];
    if (!type) throw bad('Unsupported audio format.');
    await purge().catch(() => {});
    const path = `${sectionId}/${q.user.id}-${crypto.randomUUID()}.${ext}`;
    const { error } = await sb.storage.from('room-voice').upload(path, f.buffer, { contentType: type, upsert: false }); if (error) throw error;
    const { data: old } = await sb.from('room_voice').select('id,audio_url').eq('section_id', sectionId).eq('user_id', q.user.id);
    if (old?.length) { await sb.from('room_voice').delete().in('id', old.map(o => o.id)); await removeFiles(old.map(o => o.audio_url)); }
    const now = Date.now();
    const { data, error: e2 } = await sb.from('room_voice').insert({ section_id: sectionId, user_id: q.user.id, audio_url: FILES_URL + path, duration_ms: Math.min(ms, 30000),
      created_at: new Date(now).toISOString(), expires_at: new Date(now + 12 * 3600000).toISOString() }).select().single();
    if (e2) { await removeFiles([FILES_URL + path]); throw e2; }
    r.json(data);
  }));

  // delete: the author, or the adviser of that section
  app.delete('/api/room/voice/:id', wrap(async (q, r) => {
    const { data: v } = await sb.from('room_voice').select('*').eq('id', q.params.id).maybeSingle(); if (!v) throw bad('Voice message not found', 404);
    const a = await access(q, v.section_id);
    if (v.user_id !== q.user.id && !a.adviser) throw bad('You can only delete your own voice message.', 403);
    await sb.from('room_voice').delete().eq('id', v.id); await removeFiles([v.audio_url]);
    r.json({ ok: true });
  }));
};
