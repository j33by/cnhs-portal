// Student chat: the group chat of a section + private chats between classmates.
// Rules: only enrolled students of the section can read or write (teachers, parents and other sections cannot).
// Reading/realtime goes straight to Supabase (row-level security, see 016_room_chat.sql); everything that WRITES comes through here.
const crypto = require('crypto');
const { notify } = require('../services/notify');

const REACTS = ['👍', '❤️', '😂', '😮', '😢', '🙏'];
const TYPES = {                                   // allowed files -> content type (anything else is refused)
  jpg: 'image/jpeg', jpeg: 'image/jpeg', png: 'image/png', gif: 'image/gif', webp: 'image/webp', heic: 'image/heic',
  pdf: 'application/pdf', txt: 'text/plain', csv: 'text/csv',
  doc: 'application/msword', docx: 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
  xls: 'application/vnd.ms-excel', xlsx: 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
  ppt: 'application/vnd.ms-powerpoint', pptx: 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  zip: 'application/zip', mp3: 'audio/mpeg', m4a: 'audio/mp4', mp4: 'video/mp4',
};
const MAX_FILES = 5;

module.exports = function mount(app, { sb, wrap, bad, up }) {
  const FILES_URL = `${process.env.SUPABASE_URL}/storage/v1/object/public/chat-files/`;
  const snippet = (t, n = 100) => { const s = String(t || '').replace(/\s+/g, ' ').trim(); return s.length > n ? s.slice(0, n - 1) + '…' : s; };
  const pathOf = url => typeof url === 'string' && url.startsWith(FILES_URL) ? url.slice(FILES_URL.length) : null;

  // teachers of a section = its adviser + the subject teachers
  const sectionTeachers = async sid => {
    const { data: sec } = await sb.from('sections').select('adviser_id').eq('id', sid).maybeSingle();
    const { data: ss } = await sb.from('section_subjects').select('teacher_id').eq('section_id', sid);
    return [...new Set([sec?.adviser_id, ...(ss || []).map(x => x.teacher_id)].filter(Boolean))];
  };
  const teaches = async (uid, sid) => (await sectionTeachers(sid)).includes(uid);
  const shareSection = async (a, b) => {
    const mine = async u => { const [{ data: x }, { data: y }] = await Promise.all([sb.from('sections').select('id').eq('adviser_id', u), sb.from('section_subjects').select('section_id').eq('teacher_id', u)]); return new Set([...(x || []).map(r => r.id), ...(y || []).map(r => r.section_id)]); };
    const A = await mine(a), B = await mine(b); for (const id of A) if (B.has(id)) return true; return false;
  };

  // teacher <-> teacher (share a section) or teacher <-> student (a student of a section he advises/teaches)
  const teacherMayChatWith = async (tid, other) => {
    const { data: ot } = await sb.from('teachers').select('id').eq('id', other).maybeSingle(); if (ot) return shareSection(tid, other);
    const { data: os } = await sb.from('students').select('section_id,status').eq('id', other).maybeSingle();
    return !!(os?.section_id && os.status === 'enrolled' && await teaches(tid, os.section_id));
  };
  // student <-> classmate or student <-> adviser / subject teacher of my section
  const studentMayChatWith = async (m, other) => {
    const { data: os } = await sb.from('students').select('section_id,status').eq('id', other).maybeSingle();
    if (os) return os.section_id === m.section_id && os.status === 'enrolled';
    const { data: ot } = await sb.from('teachers').select('id').eq('id', other).maybeSingle();
    return !!ot && await teaches(other, m.section_id);
  };

  // the signed-in person: a student enrolled in a section, or a teacher
  const me = async q => {
    if (q.profile?.role === 'teacher') {
      const { data } = await sb.from('teachers').select('id,first_name,last_name').eq('id', q.user.id).maybeSingle();
      if (!data) throw bad('Teacher record not found.', 403);
      return { ...data, teacher: true };
    }
    if (q.profile?.role !== 'student') throw bad('Chat is for students and teachers.', 403);
    const { data } = await sb.from('students').select('id,first_name,last_name,section_id').eq('id', q.user.id).maybeSingle();
    if (!data) throw bad('Student record not found.', 403);
    if (!data.section_id) throw bad('You can chat once you are added to a section.', 403);
    return data;
  };
  // a thread I may use. Students: my section's group chat, or a private chat with a classmate. Teachers: the staff chat of a section I teach, or a private chat with a teacher who shares a section with me.
  const thread = async (q, id) => {
    const m = await me(q);
    const { data: t } = await sb.from('chat_threads').select('*').eq('id', id).maybeSingle(); if (!t) throw bad('Chat not found', 404);
    if (m.teacher) {
      if (t.kind === 'staff') { if (!(await teaches(m.id, t.section_id))) throw bad('Chat not found', 404); }
      else if (t.kind === 'private') {
        if (![t.user_a, t.user_b].includes(m.id)) throw bad('Chat not found', 404);
        const other = t.user_a === m.id ? t.user_b : t.user_a;
        if (!(await teacherMayChatWith(m.id, other))) throw bad('You no longer share a section with this person.', 403);
      } else throw bad('Chat not found', 404);
      return { m, t };
    }
    if (t.kind === 'group') { if (t.section_id !== m.section_id) throw bad('Chat not found', 404); }
    else if (t.kind === 'private') {
      if (![t.user_a, t.user_b].includes(m.id)) throw bad('Chat not found', 404);
      const other = t.user_a === m.id ? t.user_b : t.user_a;
      if (!(await studentMayChatWith(m, other))) throw bad('This person is no longer in your section.', 403);
    } else throw bad('Chat not found', 404);
    return { m, t };
  };
  const message = async (q, id) => {
    const { data: msg } = await sb.from('chat_messages').select('*').eq('id', id).maybeSingle(); if (!msg) throw bad('Message not found', 404);
    const { m, t } = await thread(q, msg.thread_id); return { m, t, msg };
  };
  const removeFiles = async atts => { const paths = (atts || []).map(a => pathOf(a?.url)).filter(Boolean); if (paths.length) await sb.storage.from('chat-files').remove(paths).catch(() => {}); };

  // ---- open (or create) the group chat of my section
  app.post('/api/chat/group', wrap(async (q, r) => {
    const m = await me(q); if (m.teacher) throw bad('The section group chat is for students. Use the staff chat.', 403);
    let { data: t } = await sb.from('chat_threads').select('id').eq('kind', 'group').eq('section_id', m.section_id).maybeSingle();
    if (!t) {
      const ins = await sb.from('chat_threads').insert({ kind: 'group', section_id: m.section_id }).select('id').single();
      if (ins.error) { t = (await sb.from('chat_threads').select('id').eq('kind', 'group').eq('section_id', m.section_id).maybeSingle()).data; if (!t) throw ins.error; } else t = ins.data;
    }
    r.json({ id: t.id });
  }));

  // ---- teachers: open (or create) the staff chat of a section I teach
  app.post('/api/chat/staff', wrap(async (q, r) => {
    const m = await me(q); if (!m.teacher) throw bad('Staff chats are for teachers.', 403);
    const sid = String(q.body?.section_id || ''); if (!sid || !(await teaches(m.id, sid))) throw bad('You do not teach this section.', 403);
    let { data: t } = await sb.from('chat_threads').select('id').eq('kind', 'staff').eq('section_id', sid).maybeSingle();
    if (!t) {
      const ins = await sb.from('chat_threads').insert({ kind: 'staff', section_id: sid }).select('id').single();
      if (ins.error) { t = (await sb.from('chat_threads').select('id').eq('kind', 'staff').eq('section_id', sid).maybeSingle()).data; if (!t) throw ins.error; } else t = ins.data;
    }
    r.json({ id: t.id });
  }));

  // ---- open (or create) a private chat: student with a classmate, or teacher with a teacher who shares a section
  app.post('/api/chat/private', wrap(async (q, r) => {
    const m = await me(q), other = String(q.body?.user_id || '');
    if (!other || other === m.id) throw bad('Choose someone to message.');
    if (m.teacher ? !(await teacherMayChatWith(m.id, other)) : !(await studentMayChatWith(m, other))) throw bad(m.teacher ? 'You can message teachers who share a section with you and students of your sections.' : 'You can message your classmates and your teachers.', 403);
    const [a, b] = [m.id, other].sort();
    let { data: t } = await sb.from('chat_threads').select('id').eq('kind', 'private').eq('user_a', a).eq('user_b', b).maybeSingle();
    if (!t) {
      const ins = await sb.from('chat_threads').insert({ kind: 'private', user_a: a, user_b: b }).select('id').single();
      if (ins.error) { t = (await sb.from('chat_threads').select('id').eq('kind', 'private').eq('user_a', a).eq('user_b', b).maybeSingle()).data; if (!t) throw ins.error; } else t = ins.data;
    }
    r.json({ id: t.id });
  }));

  // ---- upload files for a message (multipart; the file NAME is the form field). Returns [{url,name,size,type}]
  const receive = (q, r, next) => up.any()(q, r, err => err ? r.status(err.code === 'LIMIT_FILE_SIZE' ? 413 : 400).json({ error: err.code === 'LIMIT_FILE_SIZE' ? 'A file is bigger than 10 MB.' : 'Upload failed.' }) : next());
  app.post('/api/chat/:id/upload', receive, wrap(async (q, r) => {
    const { t } = await thread(q, q.params.id), files = q.files || [];
    if (!files.length) throw bad('Choose a file.'); if (files.length > MAX_FILES) throw bad(`Up to ${MAX_FILES} files at a time.`);
    const out = [];
    for (const f of files) {
      const name = String(f.originalname || f.fieldname || 'file').replace(/[\\/\0]/g, '_').trim().slice(-80) || 'file';
      const ext = (name.split('.').pop() || '').toLowerCase(), type = TYPES[ext];
      if (!type) throw bad(`"${name}" is not allowed. You can send photos, PDF, Word, Excel, PowerPoint, text, ZIP, audio or short video.`);
      if (f.size > 10 * 1024 * 1024) throw bad(`"${name}" is bigger than 10 MB.`);
      const path = `${t.id}/${crypto.randomUUID()}-${name.replace(/[^A-Za-z0-9._-]/g, '_')}`;
      const { error } = await sb.storage.from('chat-files').upload(path, f.buffer, { contentType: type, upsert: false }); if (error) throw error;
      out.push({ url: FILES_URL + path, name, size: f.size, type });
    }
    r.json({ files: out });
  }));

  // ---- send a message (text and/or files, optionally replying to another message of the same chat)
  app.post('/api/chat/:id/messages', wrap(async (q, r) => {
    const { m, t } = await thread(q, q.params.id), b = q.body || {};
    const text = String(b.text || '').trim().slice(0, 2000);
    const atts = Array.isArray(b.attachments) ? b.attachments.slice(0, MAX_FILES) : [];
    for (const a of atts) if (!pathOf(a?.url) || !pathOf(a.url).startsWith(t.id + '/')) throw bad('Invalid file.');
    if (!text && !atts.length) throw bad('Write a message or add a file.');
    const { count } = await sb.from('chat_messages').select('id', { count: 'exact', head: true }).eq('sender_id', m.id).gte('created_at', new Date(Date.now() - 10000).toISOString());
    if ((count || 0) >= 10) throw bad('Slow down a little.', 429);
    const row = { thread_id: t.id, sender_id: m.id, sender_name: q.profile.full_name || `${m.first_name} ${m.last_name}`, sender_photo: q.profile.photo_url || null, body: text,
      attachments: atts.map(a => ({ url: a.url, name: String(a.name || 'file').slice(0, 80), size: +a.size || 0, type: String(a.type || '') })) };
    if (b.reply_to) {
      const { data: src } = await sb.from('chat_messages').select('id,thread_id,sender_name,body,attachments,deleted').eq('id', b.reply_to).maybeSingle();
      if (!src || src.thread_id !== t.id || src.deleted) throw bad('You cannot reply to that message.');
      row.reply_to = src.id; row.reply_name = src.sender_name;
      row.reply_snippet = src.body ? snippet(src.body) : (src.attachments?.[0]?.type || '').startsWith('image/') ? 'Photo' : `File: ${src.attachments?.[0]?.name || 'file'}`;
    }
    const { data, error } = await sb.from('chat_messages').insert(row).select().single(); if (error) throw error;
    await sb.from('chat_reads').upsert({ thread_id: t.id, user_id: m.id, last_read_at: data.created_at }, { onConflict: 'thread_id,user_id' });
    await notifyChat(t, m, q.profile, data).catch(() => {});                      // a failed alert must never fail the send
    r.json(data);
  }));

  // ---- in-app alert for the other students. One alert per chat while it is unread (it is updated with the newest message), so a busy group chat does not flood the inbox.
  const notifyChat = async (t, m, profile, msg) => {
    let ids;
    if (t.kind === 'private') ids = [t.user_a === m.id ? t.user_b : t.user_a];
    else if (t.kind === 'staff') ids = (await sectionTeachers(t.section_id)).filter(id => id !== m.id);
    else ids = ((await sb.from('students').select('id').eq('section_id', t.section_id).eq('status', 'enrolled')).data || []).map(x => x.id).filter(id => id !== m.id);
    if (!ids.length) return;
    const who = profile?.full_name || `${m.first_name} ${m.last_name}`.trim();
    const what = msg.body ? snippet(msg.body, 90) : (msg.attachments?.[0]?.type || '').startsWith('image/') ? 'Sent a photo' : msg.attachments?.length > 1 ? `Sent ${msg.attachments.length} files` : 'Sent a file';
    let title = who;
    if (t.kind === 'group' || t.kind === 'staff') { const { data: sec } = await sb.from('sections').select('grade_level,name').eq('id', t.section_id).maybeSingle(); title = `${sec ? `Grade ${sec.grade_level} ${sec.name} ${t.kind === 'staff' ? 'teachers' : 'group'}` : 'Group'} · ${who}`; }
    const { data: open } = await sb.from('notifications').select('id,user_id,data').eq('kind', 'chat').eq('read', false).in('user_id', ids);
    const have = new Map((open || []).filter(n => n.data?.thread_id === t.id).map(n => [n.user_id, n.id]));
    const data = { thread_id: t.id, thread_kind: t.kind, section_id: t.section_id || null, sender_id: m.id, sender_name: who, sender_photo: profile?.photo_url || null };
    for (const [uid, nid] of have) await sb.from('notifications').update({ title, body: what, data, created_at: new Date().toISOString() }).eq('id', nid);
    const fresh = ids.filter(id => !have.has(id));
    if (fresh.length) await notify(sb, fresh, { kind: 'chat', title, body: what, data });
  };

  // ---- react: one emoji per person. Send the same emoji again (or emoji: null) to take it back.
  app.put('/api/chat/messages/:id/reaction', wrap(async (q, r) => {
    const { m, msg } = await message(q, q.params.id); if (msg.deleted) throw bad('This message was deleted.');
    const emoji = q.body?.emoji ?? null; if (emoji !== null && !REACTS.includes(emoji)) throw bad('Unknown reaction.');
    const { data, error } = await sb.rpc('chat_set_reaction', { p_msg: msg.id, p_user: m.id, p_emoji: emoji }); if (error) throw error;
    r.json({ reactions: data || {} });
  }));

  // ---- delete my own message for everyone (text and files are removed; a "Message deleted" note stays)
  app.delete('/api/chat/messages/:id', wrap(async (q, r) => {
    const { m, msg } = await message(q, q.params.id); if (msg.sender_id !== m.id) throw bad('You can only delete your own messages.', 403);
    if (!msg.deleted) {
      await sb.from('chat_messages').update({ deleted: true, body: '', attachments: [], reactions: {} }).eq('id', msg.id);
      await sb.from('chat_messages').update({ reply_snippet: 'Message deleted' }).eq('reply_to', msg.id);
      await removeFiles(msg.attachments);
    }
    r.json({ ok: true });
  }));

  // ---- mark a chat as read (drives the unread dots)
  app.post('/api/chat/:id/read', wrap(async (q, r) => {
    const { m, t } = await thread(q, q.params.id);
    await sb.from('chat_reads').upsert({ thread_id: t.id, user_id: m.id, last_read_at: new Date().toISOString() }, { onConflict: 'thread_id,user_id' });
    const { data: open } = await sb.from('notifications').select('id,data').eq('user_id', m.id).eq('kind', 'chat').eq('read', false);   // opening the chat clears its alert
    const ids = (open || []).filter(n => n.data?.thread_id === t.id).map(n => n.id);
    if (ids.length) await sb.from('notifications').update({ read: true }).in('id', ids);
    r.json({ ok: true });
  }));
};
