const express = require('express'), cors = require('cors'), multer = require('multer');
const { createClient } = require('@supabase/supabase-js');
const { nextId } = require('./services/ids');
const { ingestLogs, closeDay } = require('./services/attendance');
const { parseEmployeeForm, } = require('./services/biometric');
const { buildEmployeeForm } = require('./services/xlsWriter');
const { notify } = require('./services/notify');

const sb = createClient(process.env.SUPABASE_URL, process.env.SUPABASE_SERVICE_ROLE_KEY, { auth: { persistSession: false } });
const app = express(); app.use(cors()); app.use(express.json({ limit: '2mb' }));
const up = multer({ limits: { fileSize: 10 * 1024 * 1024 } });
const wrap = f => (q, r) => f(q, r).catch(e => { console.error(e); r.status(e.status || 500).json({ error: e.message }); });
const bad = (m, s = 400) => Object.assign(new Error(m), { status: s });

// ---- auth: every request carries the Supabase (Google) access token
async function auth(req, _res, next) {
  const tok = (req.headers.authorization || '').replace('Bearer ', '');
  const { data, error } = await sb.auth.getUser(tok);
  if (error || !data.user) return next(bad('Not signed in', 401));
  const { data: p } = await sb.from('profiles').select('*').eq('id', data.user.id).maybeSingle();
  req.user = data.user; req.profile = p; next();
}
const teacherOnly = (q, _r, n) => n(q.profile?.role === 'teacher' ? undefined : bad('Teachers only', 403));
const curYear = async () => (await sb.from('school_years').select('*').eq('is_current', true).single()).data;
const freeBioId = async () => { const [{ data: a }, { data: b }] = await Promise.all([sb.from('students').select('biometric_id'), sb.from('teachers').select('biometric_id')]);
  const used = new Set([...a, ...b].map(x => x.biometric_id)); let i = 1; while (used.has(i)) i++; return i; };

app.get('/health', (_q, r) => r.json({ ok: true }));
app.use('/api', wrap(async (q, r, n) => auth(q, r, n)));

// ============ Sign-up forms (after Google sign-in) ============
app.post('/api/onboarding/teacher', wrap(async (q, r) => {
  const b = q.body; if (q.profile?.onboarded) throw bad('Already registered');
  if (!b.first_name || !b.last_name) throw bad('Name is required');
  if (!(b.subjects?.length >= 1 && b.subjects.length <= 5)) throw bad('Choose 1 to 5 subjects');
  if (!(b.grade_levels?.length >= 1 && b.grade_levels.length <= 5)) throw bad('Choose 1 to 5 grade levels');
  const id = q.user.id, no = await nextId(sb, 'teacher');
  await sb.from('profiles').upsert({ id, role: 'teacher', email: q.user.email, full_name: `${b.first_name} ${b.last_name}`, photo_url: b.photo_url, onboarded: true });
  const { error } = await sb.from('teachers').insert({ id, teacher_no: no, first_name: b.first_name, last_name: b.last_name, birthdate: b.birthdate, address: b.address,
    contact_no: b.contact_no, subjects: b.subjects, grade_levels: b.grade_levels, biometric_id: await freeBioId() });
  if (error) throw error; r.json({ teacher_no: no });
}));
app.post('/api/onboarding/student', wrap(async (q, r) => {
  const b = q.body; if (q.profile?.onboarded) throw bad('Already registered');
  if (!b.first_name || !b.last_name || !b.age || !b.address || !b.grade_level) throw bad('Name, age, address and grade level are required');
  const y = await curYear(), id = q.user.id, no = await nextId(sb, 'student', y.label);
  let section_id = null;
  if (b.section_name) { const { data: s } = await sb.from('sections').select('id').eq('school_year_id', y.id).eq('grade_level', b.grade_level).ilike('name', b.section_name).maybeSingle(); section_id = s?.id || null; }
  await sb.from('profiles').upsert({ id, role: 'student', email: q.user.email, full_name: `${b.first_name} ${b.last_name}`, photo_url: b.photo_url, onboarded: true });
  const { error } = await sb.from('students').insert({ id, student_no: no, first_name: b.first_name, middle_name: b.middle_name, last_name: b.last_name, age: b.age, sex: b.sex,
    birthdate: b.birthdate, address: b.address, lrn: b.lrn, grade_level: b.grade_level, section_id, guardian_name: b.guardian_name, guardian_contact: b.guardian_contact, biometric_id: await freeBioId() });
  if (error) throw error; r.json({ student_no: no, section_matched: !!section_id });   // unmatched section => adviser adds them
}));
app.post('/api/onboarding/parent', wrap(async (q, r) => {
  if (!q.body.full_name) throw bad('Name is required');
  await sb.from('profiles').upsert({ id: q.user.id, role: 'parent', email: q.user.email, full_name: q.body.full_name, photo_url: q.body.photo_url, onboarded: true }); r.json({ ok: true });
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
  const allow = ['first_name', 'middle_name', 'last_name', 'age', 'sex', 'address', 'guardian_name', 'guardian_contact', 'grade_level', 'status'];
  const patch = Object.fromEntries(Object.entries(q.body).filter(([k]) => allow.includes(k)));
  const { error } = await sb.from('students').update(patch).eq('id', q.params.id); if (error) throw error; r.json({ ok: true }); }));
app.delete('/api/students/:id', teacherOnly, wrap(async (q, r) => { await sb.from('students').update({ status: 'dropped', section_id: null }).eq('id', q.params.id); r.json({ ok: true }); }));   // soft delete: keeps grades/attendance, frees device row

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

// ============ Grades ============
app.post('/api/grades', teacherOnly, wrap(async (q, r) => {
  const y = await curYear(); const rows = q.body.grades.map(g => ({ ...g, school_year_id: y.id, entered_by: q.user.id, updated_at: new Date().toISOString() }));
  const { error } = await sb.from('grades').upsert(rows, { onConflict: 'student_id,subject_id,school_year_id,term' }); if (error) throw error; r.json({ saved: rows.length }); }));
app.post('/api/grades/release', teacherOnly, wrap(async (q, r) => {
  const y = await curYear(); const { section_id, subject_id, term } = q.body;
  const { data } = await sb.from('grades').update({ released: true }).match({ section_id, subject_id, term, school_year_id: y.id }).select('student_id');
  for (const g of data || []) { const { data: l } = await sb.from('parent_links').select('parent_id').eq('student_id', g.student_id).eq('status', 'approved');
    await notify(sb, [g.student_id, ...(l || []).map(x => x.parent_id)], { kind: 'grades', title: 'New grades released', body: `Term ${term} grades are now available.` }); }
  r.json({ released: data?.length || 0 }); }));

// ============ USB / biometric sync (called by the Windows app) ============
app.post('/api/usb/ingest', teacherOnly, up.fields([{ name: 'logs', maxCount: 1 }, { name: 'employee', maxCount: 1 }]), wrap(async (q, r) => {
  const out = {}; if (q.files?.logs) out.attendance = await ingestLogs(sb, q.files.logs[0].buffer.toString('utf8'));
  if (q.files?.employee) out.device_people = parseEmployeeForm(q.files.employee[0].buffer).length; r.json(out); }));
app.get('/api/usb/state', teacherOnly, wrap(async (_q, r) => r.json((await sb.from('usb_sync_state').select('*').eq('id', 1).single()).data)));
app.get('/api/usb/employee-form', teacherOnly, wrap(async (_q, r) => {
  const [{ data: st }, { data: te }, { data: se }, { data: sc }] = await Promise.all([
    sb.from('students').select('biometric_id,first_name,last_name,sections(biometric_dept_no)').eq('status', 'enrolled'),
    sb.from('teachers').select('biometric_id,first_name,last_name'), sb.from('sections').select('name,biometric_dept_no'),
    sb.from('schedules').select('day_of_week,start_time,end_time,sections(biometric_dept_no)')]);
  const people = [...st.map(s => ({ biometric_id: s.biometric_id, name: `${s.first_name} ${s.last_name}`.slice(0, 24), dept_no: s.sections?.biometric_dept_no || null })),
    ...te.map(t => ({ biometric_id: t.biometric_id, name: `${t.first_name} ${t.last_name}`.slice(0, 24), dept_no: null }))].sort((a, b) => a.biometric_id - b.biometric_id);
  const { buffer, shifts } = buildEmployeeForm({ people, sections: se.map(s => ({ dept_no: s.biometric_dept_no, name: s.name })),
    slots: sc.filter(s => s.sections).map(s => ({ dept_no: s.sections.biometric_dept_no, day_of_week: s.day_of_week, start: s.start_time.slice(0, 5), end: s.end_time.slice(0, 5) })), start: new Date() });
  const { data: stt } = await sb.from('usb_sync_state').select('version').eq('id', 1).single();
  r.set({ 'Content-Type': 'application/vnd.ms-excel', 'X-Sync-Version': String(stt.version), 'X-Shifts-Used': String(shifts.length) }).send(buffer); }));
app.post('/api/usb/written', teacherOnly, wrap(async (q, r) => { await sb.from('usb_sync_state').update({ dirty: false }).eq('id', 1).lte('version', q.body.version); r.json({ ok: true }); }));
app.post('/api/attendance/close-day', teacherOnly, wrap(async (q, r) => r.json(await closeDay(sb, q.body.date || new Date(Date.now() + 8 * 36e5).toISOString().slice(0, 10)))));

// Render free instances sleep, so also close the day at 17:30 PH time while awake
setInterval(async () => { const n = new Date(Date.now() + 8 * 36e5); if (n.getUTCHours() === 17 && n.getUTCMinutes() === 30) closeDay(sb, n.toISOString().slice(0, 10)).catch(console.error); }, 60000);
app.listen(process.env.PORT || 3000, () => console.log('CNHS API up'));
