const express = require('express'), cors = require('cors'), multer = require('multer');
const { createClient } = require('@supabase/supabase-js');
const { nextId } = require('./services/ids');
const { ingestLogs, closeDay, relinkPunches } = require('./services/attendance');
const { parseEmployeeForm, } = require('./services/biometric');
const { buildEmployeeForm } = require('./services/xlsWriter');
const { notify } = require('./services/notify');
const mountClasses = require('./routes/classes');
const { cleanProfile } = require('./services/profile');

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const app = express(); app.use(cors()); app.use(express.json({ limit: '2mb' }));
const up = multer({ limits: { fileSize: 10 * 1024 * 1024 } });
const wrap = f => (q, r) => f(q, r).catch(e => { console.error(e); r.status(e.status || 500).json({ error: e.message }); });
const bad = (m, s = 400) => Object.assign(new Error(m), { status: s });

// ---- auth: every request carries the Supabase (Google) access token
async function auth(req, res, next) {
  try {
    const tok = (req.headers.authorization || '').replace('Bearer ', '');
    if (!tok) return res.status(401).json({ error: 'Not signed in' });
    const { data, error } = await sb.auth.getUser(tok);
    if (error || !data?.user) return res.status(401).json({ error: 'Session expired. Please sign in again.' });
    const { data: p } = await sb.from('profiles').select('*').eq('id', data.user.id).maybeSingle();
    req.user = data.user; req.profile = p; next();
  } catch (e) { console.error(e); res.status(500).json({ error: e.message }); }
}
const teacherOnly = (q, r, n) => q.profile?.role === 'teacher' ? n() : r.status(403).json({ error: 'Teachers only' });
const curYear = async () => (await sb.from('school_years').select('*').eq('is_current', true).single()).data;
// Device (fingerprint terminal) IDs are separate from school IDs. New people get a number ABOVE every ID the terminal already uses,
// so they can never collide with someone already enrolled there. Existing device IDs are attached with /api/device/link.
const freeBioId = async () => {
  let max = 0;
  for (const [t, c] of [['students', 'biometric_id'], ['teachers', 'biometric_id'], ['device_people', 'biometric_id'], ['attendance', 'biometric_id']]) {
    const { data } = await sb.from(t).select(c).not(c, 'is', null).order(c, { ascending: false }).limit(1); if (data?.[0]) max = Math.max(max, data[0][c]); }
  return max + 1;
};
const adviserOfStudent = async (uid, sid) => { const { data } = await sb.from('students').select('section_id,sections(adviser_id)').eq('id', sid).maybeSingle();
  if (!data) throw bad('Student not found', 404); if (data.section_id && data.sections?.adviser_id !== uid) throw bad("Only the student's adviser can change this record", 403); };

// Teacher subjects are typed by the teacher: [{code:'MATH7', name:'Mathematics 7'}], 1 to 5.
const cleanSubjects = list => {
  if (!Array.isArray(list)) throw bad('Add at least one subject');
  const rows = list.map(x => ({ code: String(x?.code || '').trim().toUpperCase().replace(/\s+/g, '_'), name: String(x?.name || '').trim() })).filter(x => x.code || x.name);
  if (rows.length < 1 || rows.length > 5) throw bad('Add 1 to 5 subjects');
  for (const x of rows) {
    if (!x.name || x.name.length > 60) throw bad('Every subject needs a name (up to 60 characters)');
    if (!/^[A-Z0-9_.-]{2,20}$/.test(x.code)) throw bad(`Subject code for "${x.name}" must be 2-20 letters or numbers, e.g. MATH7`);
  }
  if (new Set(rows.map(x => x.code)).size !== rows.length) throw bad('Two subjects have the same code');
  return rows;
};
app.get('/health', (_q, r) => r.json({ ok: true }));
app.use('/api', auth);

// ============ Sign-up forms (after Google sign-in) ============
app.post('/api/onboarding/teacher', wrap(async (q, r) => {
  const b = q.body; if (q.profile?.onboarded) throw bad('Already registered');
  if (!b.first_name?.trim() || !b.last_name?.trim()) throw bad('Name is required');
  const subjects = cleanSubjects(b.subjects);
  if (!(b.grade_levels?.length >= 1 && b.grade_levels.length <= 5)) throw bad('Choose 1 to 5 grade levels');
  const id = q.user.id, no = await nextId(sb, 'teacher');
  // onboarded stays false until every row is saved, so a failed attempt can simply be retried
  await sb.from('profiles').upsert({ id, role: 'teacher', email: q.user.email, full_name: `${b.first_name} ${b.last_name}`.trim(), photo_url: b.photo_url, onboarded: false });
  await sb.from('teachers').delete().eq('id', id);
  const { error } = await sb.from('teachers').insert({ id, teacher_no: no, first_name: b.first_name.trim(), last_name: b.last_name.trim(), birthdate: b.birthdate || null, address: b.address,
    contact_no: b.contact_no, grade_levels: b.grade_levels, biometric_id: await freeBioId() });
  if (error) throw error;
  const { error: e2 } = await sb.from('teacher_subjects').insert(subjects.map(x => ({ ...x, teacher_id: id })));
  if (e2) { await sb.from('teachers').delete().eq('id', id); throw e2; }
  await sb.from('profiles').update({ onboarded: true }).eq('id', id);
  r.json({ teacher_no: no });
}));
// "My subjects" tab: replace this teacher's list (1-5, typed name + code)
app.put('/api/my-subjects', teacherOnly, wrap(async (q, r) => {
  const rows = cleanSubjects(q.body.subjects).map(x => ({ ...x, teacher_id: q.user.id }));
  const { error } = await sb.from('teacher_subjects').upsert(rows, { onConflict: 'teacher_id,code' }); if (error) throw error;
  await sb.from('teacher_subjects').delete().eq('teacher_id', q.user.id).not('code', 'in', `(${rows.map(x => x.code).join(',')})`);
  r.json({ saved: rows.length });
}));
app.post('/api/onboarding/student', wrap(async (q, r) => {
  const b = q.body; if (q.profile?.onboarded) throw bad('Already registered');
  const missing = [['first_name', 'first name'], ['last_name', 'last name'], ['age', 'age'], ['address', 'address'], ['grade_level', 'grade level']].filter(([k]) => !b[k] || (typeof b[k] === 'string' && !b[k].trim())).map(x => x[1]);
  if (missing.length) throw bad('Missing: ' + missing.join(', '));
  const y = await curYear(), id = q.user.id, no = await nextId(sb, 'student', y.label);
  let section_id = null;
  if (b.section_id) { const { data: sec } = await sb.from('sections').select('id,grade_level').eq('id', b.section_id).maybeSingle(); if (sec && sec.grade_level === b.grade_level) section_id = sec.id; }
  await sb.from('profiles').upsert({ id, role: 'student', email: q.user.email, full_name: `${b.first_name} ${b.last_name}`, photo_url: b.photo_url, onboarded: false });
  await sb.from('students').delete().eq('id', id);
  const { error } = await sb.from('students').insert({ id, student_no: no, first_name: b.first_name, middle_name: b.middle_name, last_name: b.last_name, age: b.age, sex: b.sex,
    birthdate: b.birthdate || null, address: b.address, lrn: b.lrn || null, grade_level: b.grade_level, section_id, guardian_name: b.guardian_name, guardian_contact: b.guardian_contact, biometric_id: await freeBioId() });
  if (error) throw error;
  await sb.from('profiles').update({ onboarded: true }).eq('id', id);
  r.json({ student_no: no, section_matched: !!section_id });   // unmatched section => adviser adds them
}));
app.post('/api/onboarding/parent', wrap(async (q, r) => {
  if (!q.body.full_name) throw bad('Name is required');
  await sb.from('profiles').upsert({ id: q.user.id, role: 'parent', email: q.user.email, full_name: q.body.full_name, photo_url: q.body.photo_url, contact_no: q.body.contact_no || null, onboarded: true }); r.json({ ok: true });
}));
// View/edit your OWN profile. IDs, device ID, grade/section for students are not editable here.
app.patch('/api/me', wrap(async (q, r) => {
  const p = q.profile; if (!p?.onboarded) throw bad('Finish registration first');
  const b = q.body || {};
  if (b.photo_url !== undefined) {
    if (b.photo_url !== null && !(typeof b.photo_url === 'string' && b.photo_url.startsWith(process.env.SUPABASE_URL))) throw bad('Invalid photo');
    await sb.from('profiles').update({ photo_url: b.photo_url }).eq('id', q.user.id);
  }
  const f = cleanProfile(p.role, b);
  if (p.role === 'parent') { if (Object.keys(f).length) await sb.from('profiles').update(f).eq('id', q.user.id); }
  else if (Object.keys(f).length) {
    const { data, error } = await sb.from(p.role === 'student' ? 'students' : 'teachers').update(f).eq('id', q.user.id).select('first_name,last_name').single();
    if (error) throw error;
    await sb.from('profiles').update({ full_name: `${data.first_name} ${data.last_name}` }).eq('id', q.user.id);
  }
  r.json({ ok: true });
}));
app.post('/api/device-token', wrap(async (q, r) => { await sb.from('profiles').update({ fcm_token: q.body.token }).eq('id', q.user.id); r.json({ ok: true }); }));

// ============ Parent binding ============
app.post('/api/parent/bind', wrap(async (q, r) => {
  if (q.profile?.role !== 'parent') throw bad('Parents only', 403);
  const { data: s } = await sb.from('students').select('id,first_name,last_name,section_id,sections(adviser_id)').eq('student_no', (q.body.student_no || '').trim()).maybeSingle();
  if (!s) throw bad('No student with that ID number', 404);
  const { error } = await sb.from('parent_links').insert({ parent_id: q.user.id, student_id: s.id });
  if (error?.code === '23505') throw bad('You already requested this student'); if (error) throw error;
  const { data: all } = await sb.from('teachers').select('id');
  await notify(sb, [s.sections?.adviser_id || null, ...(s.sections?.adviser_id ? [] : (all || []).map(t => t.id))], { kind: 'bind', title: 'Parent bind request', body: `${q.profile.full_name} wants to link to ${s.first_name} ${s.last_name}.` });
  r.json({ ok: true });
}));
app.post('/api/bind/:id/review', teacherOnly, wrap(async (q, r) => {
  const ok = q.body.approve === true;
  const { data: l, error } = await sb.from('parent_links').update({ status: ok ? 'approved' : 'rejected', reviewed_by: q.user.id, reviewed_at: new Date().toISOString() }).eq('id', q.params.id).select('*, students(first_name)').single();
  if (error) throw error;
  await notify(sb, [l.parent_id], { kind: 'bind', title: ok ? 'Request approved' : 'Request declined', body: ok ? `You can now view ${l.students.first_name}'s attendance and grades.` : 'The teacher declined your request.' });
  r.json({ ok: true });
}));

// ============ Teachers manage advisory / students / schedules ============
app.post('/api/sections', teacherOnly, wrap(async (q, r) => {
  const y = await curYear(); const { grade_level, name, homeroom } = q.body; if (!grade_level || !name) throw bad('Grade level and section name required');
  const { data: used } = await sb.from('sections').select('biometric_dept_no'); const taken = new Set(used.map(u => u.biometric_dept_no));
  let dept = 1; while (taken.has(dept)) dept++; if (dept > 16) throw bad('The biometric device supports 16 departments');
  const { data, error } = await sb.from('sections').insert({ school_year_id: y.id, grade_level, name, homeroom, adviser_id: q.user.id, biometric_dept_no: dept }).select().single();
  if (error) throw error; r.json(data);
}));
const mySection = async (q) => { const { data } = await sb.from('sections').select('*').eq('id', q.params.id).single();
  if (!data) throw bad('Section not found', 404); if (data.adviser_id !== q.user.id) throw bad('Only the adviser can change this section', 403); return data; };
app.patch('/api/sections/:id', teacherOnly, wrap(async (q, r) => { await mySection(q); const { name, homeroom } = q.body;
  const { data, error } = await sb.from('sections').update({ name, homeroom }).eq('id', q.params.id).select().single(); if (error) throw error; r.json(data); }));
app.delete('/api/sections/:id', teacherOnly, wrap(async (q, r) => { await mySection(q); await sb.from('students').update({ section_id: null }).eq('section_id', q.params.id);
  await sb.from('sections').delete().eq('id', q.params.id); r.json({ ok: true }); }));
app.post('/api/sections/:id/students', teacherOnly, wrap(async (q, r) => {         // add / homeroom by student ID
  const s = await mySection(q); const { data: st } = await sb.from('students').select('id').eq('student_no', q.body.student_no).maybeSingle();
  if (!st) throw bad('Student ID not found', 404);
  await sb.from('students').update({ section_id: s.id, grade_level: s.grade_level }).eq('id', st.id);
  await notify(sb, [st.id], { kind: 'section', title: 'Added to a section', body: `You are now in Grade ${s.grade_level} - ${s.name}.` }); r.json({ ok: true }); }));
app.delete('/api/sections/:id/students/:sid', teacherOnly, wrap(async (q, r) => { await mySection(q); await sb.from('students').update({ section_id: null }).eq('id', q.params.sid); r.json({ ok: true }); }));
app.patch('/api/students/:id', teacherOnly, wrap(async (q, r) => {
  await adviserOfStudent(q.user.id, q.params.id);
  const allow = ['first_name', 'middle_name', 'last_name', 'age', 'sex', 'address', 'guardian_name', 'guardian_contact', 'grade_level', 'status'];
  const patch = Object.fromEntries(Object.entries(q.body).filter(([k]) => allow.includes(k)));
  const { error } = await sb.from('students').update(patch).eq('id', q.params.id); if (error) throw error; r.json({ ok: true }); }));
app.delete('/api/students/:id', teacherOnly, wrap(async (q, r) => { await adviserOfStudent(q.user.id, q.params.id); await sb.from('students').update({ status: 'dropped', section_id: null }).eq('id', q.params.id); r.json({ ok: true }); }));   // soft delete: keeps grades/attendance, frees device row

app.post('/api/sections/:id/subjects', teacherOnly, wrap(async (q, r) => {          // assign a teacher to a subject of this section
  await mySection(q); const { code, name, teacher_id } = q.body;
  const { data: sub } = await sb.from('subjects').upsert({ code, name }, { onConflict: 'code' }).select().single();
  await sb.from('section_subjects').upsert({ section_id: q.params.id, subject_id: sub.id, teacher_id }, { onConflict: 'section_id,subject_id' });
  if (teacher_id) await notify(sb, [teacher_id], { kind: 'section', title: 'New teaching assignment', body: `You were assigned ${name}.` }); r.json({ ok: true }); }));
app.post('/api/sections/:id/schedules', teacherOnly, wrap(async (q, r) => {
  await mySection(q); const b = q.body; if (!(b.start_time < b.end_time)) throw bad('End time must be after start time');
  const { data: clash } = await sb.from('schedules').select('id').eq('section_id', q.params.id).eq('day_of_week', b.day_of_week).lt('start_time', b.end_time).gt('end_time', b.start_time);
  if (clash?.length) throw bad('That time overlaps another class in this section', 409);
  const { data, error } = await sb.from('schedules').insert({ section_id: q.params.id, subject_id: b.subject_id, teacher_id: b.teacher_id, day_of_week: b.day_of_week, start_time: b.start_time, end_time: b.end_time, room: b.room }).select().single();
  if (error) throw error; r.json(data); }));
app.delete('/api/schedules/:id', teacherOnly, wrap(async (q, r) => {
  const { data: s } = await sb.from('schedules').select('section_id,sections(adviser_id)').eq('id', q.params.id).single();
  if (!s) throw bad('Schedule not found', 404); if (s.sections.adviser_id !== q.user.id) throw bad('Only the adviser can change this schedule', 403);
  await sb.from('schedules').delete().eq('id', q.params.id); r.json({ ok: true }); }));

mountClasses(app, { sb, wrap, bad, teacherOnly, curYear });   // class record, subject + homeroom attendance, grades

// ============ USB / biometric sync (called by the Windows app) ============
app.post('/api/usb/ingest', teacherOnly, up.fields([{ name: 'logs', maxCount: 1 }, { name: 'employee', maxCount: 1 }]), wrap(async (q, r) => {
  const out = {}; if (q.files?.logs) out.attendance = await ingestLogs(sb, q.files.logs[0].buffer.toString('utf8'));
  if (q.files?.employee) { const ppl = parseEmployeeForm(q.files.employee[0].buffer);
    if (ppl.length) await sb.from('device_people').upsert(ppl.map(p => ({ biometric_id: p.biometric_id, name: p.name, dept_no: p.dept_no, last_seen: new Date().toISOString() })), { onConflict: 'biometric_id' });
    out.device_people = ppl.length; }
  r.json(out); }));
// Attach a device ID that already exists on the terminal to a student or teacher (or detach it)
app.post('/api/device/link', teacherOnly, wrap(async (q, r) => {
  const { biometric_id, kind, id } = q.body; if (!Number.isInteger(biometric_id) || biometric_id < 1) throw bad('Invalid device ID');
  const table = kind === 'teacher' ? 'teachers' : 'students';
  const { data: used } = await sb.from('students').select('id').eq('biometric_id', biometric_id).neq('id', id || '00000000-0000-0000-0000-000000000000');
  const { data: usedT } = await sb.from('teachers').select('id').eq('biometric_id', biometric_id).neq('id', id || '00000000-0000-0000-0000-000000000000');
  if (used?.length || usedT?.length) throw bad('That device ID is already linked to someone else');
  const { data: me, error } = await sb.from(table).update({ biometric_id }).eq('id', id).select('id,first_name,section_id,sections(name)').single(); if (error) throw error;
  if (kind !== 'teacher') await relinkPunches(sb, me, biometric_id);
  else await sb.from('attendance').update({ teacher_id: id }).eq('biometric_id', biometric_id).is('teacher_id', null);
  r.json({ ok: true });
}));
app.post('/api/device/unlink', teacherOnly, wrap(async (q, r) => {
  const { kind, id } = q.body; await sb.from(kind === 'teacher' ? 'teachers' : 'students').update({ biometric_id: null }).eq('id', id); r.json({ ok: true }); }));
app.get('/api/usb/state', teacherOnly, wrap(async (_q, r) => r.json((await sb.from('usb_sync_state').select('*').eq('id', 1).single()).data)));
app.get('/api/usb/employee-form', teacherOnly, wrap(async (_q, r) => {
  const [{ data: st }, { data: te }, { data: se }, { data: sc }] = await Promise.all([
    sb.from('students').select('biometric_id,first_name,last_name,sections(biometric_dept_no)').eq('status', 'enrolled').not('biometric_id', 'is', null),
    sb.from('teachers').select('biometric_id,first_name,last_name').not('biometric_id', 'is', null), sb.from('sections').select('name,biometric_dept_no'),
    sb.from('schedules').select('day_of_week,start_time,end_time,sections(biometric_dept_no)')]);
  const { data: dev } = await sb.from('device_people').select('*');
  const linked = new Set([...st, ...te].map(x => x.biometric_id));
  const people = [...(dev || []).filter(d => !linked.has(d.biometric_id)).map(d => ({ biometric_id: d.biometric_id, name: (d.name || '').slice(0, 24), dept_no: d.dept_no })),
    ...st.map(s => ({ biometric_id: s.biometric_id, name: `${s.first_name} ${s.last_name}`.slice(0, 24), dept_no: s.sections?.biometric_dept_no || null })),
    ...te.map(t => ({ biometric_id: t.biometric_id, name: `${t.first_name} ${t.last_name}`.slice(0, 24), dept_no: null }))].sort((a, b) => a.biometric_id - b.biometric_id);
  const { buffer, shifts } = buildEmployeeForm({ people, sections: se.map(s => ({ dept_no: s.biometric_dept_no, name: s.name })),
    slots: sc.filter(s => s.sections).map(s => ({ dept_no: s.sections.biometric_dept_no, day_of_week: s.day_of_week, start: s.start_time.slice(0, 5), end: s.end_time.slice(0, 5) })), start: new Date() });
  const { data: stt } = await sb.from('usb_sync_state').select('version').eq('id', 1).single();
  r.set({ 'Content-Type': 'application/vnd.ms-excel', 'X-Sync-Version': String(stt.version), 'X-Shifts-Used': String(shifts.length) }).send(buffer); }));
app.post('/api/usb/written', teacherOnly, wrap(async (q, r) => { await sb.from('usb_sync_state').update({ dirty: false }).eq('id', 1).lte('version', q.body.version); r.json({ ok: true }); }));
app.post('/api/attendance/close-day', teacherOnly, wrap(async (q, r) => r.json(await closeDay(sb, q.body.date || new Date(Date.now() + 8 * 36e5).toISOString().slice(0, 10)))));

app.use((err, _q, r, _n) => { console.error(err); r.status(err.status || 500).json({ error: err.message || 'Server error' }); });
app.listen(process.env.PORT || 3000, () => console.log('CNHS API up'));
