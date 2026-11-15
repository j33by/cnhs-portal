// Teacher class records, subject attendance (+absence policy), homeroom attendance, grades. Ported from the PHP portal.
const { MAX_RECORD_COLS, recPercent, transmute, standingOf, isWeekday, phToday, validDate } = require('../services/records');
const { notify } = require('../services/notify');
const { parentsOf } = require('../services/attendance');
const ST = ['P', 'A', 'L', 'E'];

module.exports = function mount(app, { sb, wrap, bad, teacherOnly, curYear }) {
  // The teacher must be assigned to this subject in this section (the adviser assigns them).
  const myClass = async (uid, section_id, subject_id) => {
    const { data } = await sb.from('section_subjects').select('teacher_id,sections(school_year_id,grade_level,name),subjects(code,name)').match({ section_id, subject_id }).maybeSingle();
    if (!data || data.teacher_id !== uid) throw bad('You are not assigned to this class', 403); return data;
  };
  const classStudents = async section_id => (await sb.from('students').select('id,student_no,first_name,last_name,sex').eq('section_id', section_id).eq('status', 'enrolled')
    .order('sex', { ascending: false }).order('last_name').order('first_name')).data || [];
  const lockedTerm = async (section_id, subject_id, term) => ((await sb.from('grades').select('id', { count: 'exact', head: true }).match({ section_id, subject_id, term, released: true })).count || 0) > 0;
  const checkDate = d => { if (!validDate(d) || d > phToday()) throw bad('Choose a valid date that is not in the future.'); if (!isWeekday(d)) throw bad('Classes are held Monday to Friday. Pick a weekday.'); };

  // ---- Subject attendance (per class, per date) + absence rule
  app.put('/api/class-policy', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, free_absences, apply_to_record } = q.body; const c = await myClass(q.user.id, section_id, subject_id);
    if (!(free_absences >= 1 && free_absences <= 100)) throw bad('Allowed absences must be between 1 and 100.');
    await sb.from('class_policy').upsert({ section_id, subject_id, school_year_id: c.sections.school_year_id, free_absences, apply_to_record: !!apply_to_record, updated_by: q.user.id });
    r.json({ dropped: await applyStanding(section_id, subject_id, c) });
  }));
  async function applyStanding(section_id, subject_id, c) {            // same as PHP apply_standing: over the limit => student marked dropped (only if the rule says so)
    const yid = c.sections.school_year_id;
    const { data: pol } = await sb.from('class_policy').select('*').match({ section_id, subject_id, school_year_id: yid }).maybeSingle();
    if (!pol?.apply_to_record) return 0;
    const { data: rows } = await sb.from('class_attendance').select('student_id').match({ section_id, subject_id, school_year_id: yid, status: 'A' });
    const n = {}; for (const x of rows || []) n[x.student_id] = (n[x.student_id] || 0) + 1; let dropped = 0;
    for (const [sid, a] of Object.entries(n)) if (standingOf(a, pol.free_absences) === 'dropped') {
      const { data } = await sb.from('students').update({ status: 'dropped' }).eq('id', sid).eq('status', 'enrolled').select('id'); dropped += data?.length || 0; }
    return dropped;
  }
  app.post('/api/class-attendance', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, dates } = q.body;                  // dates: [{date, entries:[{student_id,status,remarks}]}]
    const c = await myClass(q.user.id, section_id, subject_id); const ok = new Set((await classStudents(section_id)).map(s => s.id)); let n = 0;
    if (!dates?.length) throw bad('Nothing to save. Add a date column first.');
    const seen = new Set(); for (const d of dates) { checkDate(d.date); if (seen.has(d.date)) throw bad(`${d.date} appears twice. Keep one column per date.`); seen.add(d.date); }
    for (const d of dates) {
      const rows = d.entries.filter(e => ok.has(e.student_id) && ST.includes(e.status)).map(e => ({ student_id: e.student_id, section_id, subject_id, school_year_id: c.sections.school_year_id, att_date: d.date, status: e.status, remarks: (e.remarks || '').slice(0, 120) || null, marked_by: q.user.id, updated_at: new Date().toISOString() }));
      if (rows.length) { const { error } = await sb.from('class_attendance').upsert(rows, { onConflict: 'student_id,subject_id,att_date' }); if (error) throw error; n += rows.length; }
    }
    r.json({ saved: n, dropped: await applyStanding(section_id, subject_id, c) });
  }));
  app.delete('/api/class-attendance', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, date } = q.query; await myClass(q.user.id, section_id, subject_id);
    await sb.from('class_attendance').delete().match({ section_id, subject_id, att_date: date }); r.json({ ok: true });
  }));

  // ---- Homeroom (daily) attendance by the adviser; biometric times stay attached
  app.post('/api/attendance/homeroom', teacherOnly, wrap(async (q, r) => {
    const { section_id, date, entries } = q.body; checkDate(date);
    const { data: sec } = await sb.from('sections').select('adviser_id,name').eq('id', section_id).single();
    if (sec?.adviser_id !== q.user.id) throw bad('Only the adviser can mark homeroom attendance.', 403);
    const ok = new Map((await classStudents(section_id)).map(s => [s.id, s]));
    const { data: old } = await sb.from('daily_attendance').select('student_id,status').eq('att_date', date).in('student_id', [...ok.keys()]);
    const was = new Map((old || []).map(o => [o.student_id, o.status])); let n = 0;
    const rows = entries.filter(e => ok.has(e.student_id) && ST.includes(e.status)).map(e => ({ student_id: e.student_id, section_id, att_date: date, status: e.status, remarks: (e.remarks || '').slice(0, 120) || null, source: 'manual', marked_by: q.user.id, updated_at: new Date().toISOString() }));
    if (rows.length) { const { error } = await sb.from('daily_attendance').upsert(rows, { onConflict: 'student_id,att_date' }); if (error) throw error; n = rows.length; }
    if (date >= new Date(Date.now() + 8 * 36e5 - 2 * 864e5).toISOString().slice(0, 10))   // tell families only about recent days that actually changed
      for (const e of rows) if (was.get(e.student_id) !== e.status && e.status !== 'P') {
        const s = ok.get(e.student_id); await notify(sb, [s.id, ...await parentsOf(sb, s.id)], { kind: 'attendance',
          title: `${s.first_name} is ${e.status === 'A' ? 'absent' : e.status === 'L' ? 'late' : 'excused'}`, body: `Marked by the adviser for ${date}.`, data: { student_id: s.id, date, status: e.status } }); }
    r.json({ saved: n });
  }));

  // ---- Class record: columns (quiz, seatwork...) and scores
  app.post('/api/record/columns', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, term, title, col_date, max_score, weight = 1 } = q.body; const c = await myClass(q.user.id, section_id, subject_id);
    if (!title?.trim() || !validDate(col_date)) throw bad('Enter a column title and a valid date.');
    if (!(max_score > 0 && max_score <= 1000)) throw bad('Highest possible score must be between 1 and 1000.');
    if (!(weight > 0 && weight <= 10)) throw bad('Weight must be between 0.1 and 10.');
    const { count } = await sb.from('record_columns').select('id', { count: 'exact', head: true }).match({ section_id, subject_id, term, school_year_id: c.sections.school_year_id, is_deleted: false });
    if (count >= MAX_RECORD_COLS) throw bad(`A class record can have at most ${MAX_RECORD_COLS} columns per term.`);
    const { data, error } = await sb.from('record_columns').insert({ section_id, subject_id, term, title: title.trim().slice(0, 60), col_date, max_score, weight, school_year_id: c.sections.school_year_id, created_by: q.user.id }).select().single();
    if (error) throw error; r.json(data);
  }));
  const myColumn = async (q) => { const { data: col } = await sb.from('record_columns').select('*').eq('id', q.params.id).eq('is_deleted', false).maybeSingle();
    if (!col) throw bad('Column not found', 404); await myClass(q.user.id, col.section_id, col.subject_id); return col; };
  app.patch('/api/record/columns/:id', teacherOnly, wrap(async (q, r) => {
    const col = await myColumn(q); const { title, col_date, max_score, weight } = q.body;
    if (!title?.trim() || !validDate(col_date) || !(max_score > 0 && max_score <= 1000) || !(weight > 0 && weight <= 10)) throw bad('Check the title, date, highest score and weight.');
    const { data: top } = await sb.from('record_scores').select('score').eq('column_id', col.id).order('score', { ascending: false }).limit(1);
    if (top?.[0] && max_score < +top[0].score) throw bad(`Highest possible score cannot be lower than a score already entered (${top[0].score}).`);
    await sb.from('record_columns').update({ title: title.trim().slice(0, 60), col_date, max_score, weight }).eq('id', col.id); r.json({ ok: true });
  }));
  app.delete('/api/record/columns/:id', teacherOnly, wrap(async (q, r) => { const col = await myColumn(q); await sb.from('record_columns').update({ is_deleted: true }).eq('id', col.id); r.json({ ok: true }); }));

  app.put('/api/record/scores', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, term, scores } = q.body;           // scores: [{column_id, student_id, score|null}]
    const c = await myClass(q.user.id, section_id, subject_id);
    const { data: cols } = await sb.from('record_columns').select('id,max_score').match({ section_id, subject_id, term, school_year_id: c.sections.school_year_id, is_deleted: false });
    const max = new Map(cols.map(x => [x.id, +x.max_score])), studs = new Set((await classStudents(section_id)).map(s => s.id));
    const bads = scores.filter(s => !max.has(s.column_id) || !studs.has(s.student_id) || (s.score != null && !(s.score >= 0 && s.score <= max.get(s.column_id))));
    if (bads.length) throw bad('Scores must be between 0 and the highest possible score. Nothing was saved.');
    const sets = scores.filter(s => s.score != null).map(s => ({ column_id: s.column_id, student_id: s.student_id, score: Math.round(s.score * 100) / 100 }));
    if (sets.length) { const { error } = await sb.from('record_scores').upsert(sets); if (error) throw error; }
    for (const s of scores.filter(s => s.score == null)) await sb.from('record_scores').delete().match({ column_id: s.column_id, student_id: s.student_id });
    r.json({ changes: scores.length });
  }));
  app.post('/api/record/push-grade', teacherOnly, wrap(async (q, r) => {   // class record -> term grade (weighted %, optionally transmuted 60->75)
    const { section_id, subject_id, term, transmute: tr } = q.body; const c = await myClass(q.user.id, section_id, subject_id);
    if (await lockedTerm(section_id, subject_id, term)) throw bad(`Term ${term} grades are released. Unrelease them before editing.`);
    const yid = c.sections.school_year_id;
    const { data: cols } = await sb.from('record_columns').select('*').match({ section_id, subject_id, term, school_year_id: yid, is_deleted: false });
    const { data: sc } = cols.length ? await sb.from('record_scores').select('*').in('column_id', cols.map(x => x.id)) : { data: [] };
    const scores = {}; for (const s of sc) (scores[s.column_id] ||= {})[s.student_id] = +s.score;
    const rows = []; for (const s of await classStudents(section_id)) { const p = recPercent(cols, scores, s.id); if (p == null) continue;
      rows.push({ student_id: s.id, subject_id, section_id, school_year_id: yid, term, grade: Math.round((tr ? transmute(p) : p) * 100) / 100, entered_by: q.user.id, updated_at: new Date().toISOString() }); }
    if (rows.length) { const { error } = await sb.from('grades').upsert(rows, { onConflict: 'student_id,subject_id,school_year_id,term' }); if (error) throw error; }
    r.json({ saved: rows.length });
  }));

  // ---- Grades: direct entry, release / unrelease (release notifies students + parents)
  app.post('/api/grades', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, term, grades } = q.body; const c = await myClass(q.user.id, section_id, subject_id);   // grades: [{student_id, grade|null}]
    if (await lockedTerm(section_id, subject_id, term)) throw bad(`Term ${term} grades are released. Unrelease them before editing.`);
    const studs = new Set((await classStudents(section_id)).map(s => s.id));
    if (grades.some(g => !studs.has(g.student_id) || (g.grade != null && !(g.grade >= 0 && g.grade <= 100)))) throw bad('Grades must be numbers from 0 to 100. Nothing was saved.');
    const yid = c.sections.school_year_id;
    const sets = grades.filter(g => g.grade != null).map(g => ({ student_id: g.student_id, subject_id, section_id, school_year_id: yid, term, grade: Math.round(g.grade * 100) / 100, entered_by: q.user.id, updated_at: new Date().toISOString() }));
    if (sets.length) { const { error } = await sb.from('grades').upsert(sets, { onConflict: 'student_id,subject_id,school_year_id,term' }); if (error) throw error; }
    for (const g of grades.filter(g => g.grade == null)) await sb.from('grades').delete().match({ student_id: g.student_id, subject_id, school_year_id: yid, term });
    r.json({ saved: grades.length });
  }));
  app.post('/api/grades/release', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, term, released = true } = q.body; const c = await myClass(q.user.id, section_id, subject_id);
    const { data } = await sb.from('grades').update({ released }).match({ section_id, subject_id, term, school_year_id: c.sections.school_year_id }).select('student_id');
    if (released) for (const g of data || []) await notify(sb, [g.student_id, ...await parentsOf(sb, g.student_id)], { kind: 'grades', title: 'New grades released', body: `${c.subjects.name}: Term ${term} grade is now available.` });
    r.json({ count: data?.length || 0 });
  }));
};
