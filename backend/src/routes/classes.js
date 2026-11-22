// Teacher class records, subject attendance (+absence policy), homeroom attendance, grades. Ported from the PHP portal.
const { MAX_RECORD_COLS, recPercent, transmute, standingOf, isWeekday, phToday, validDate } = require('../services/records');
const { notify } = require('../services/notify');
const { parentsOf, parentsOfMany } = require('../services/attendance');
const { applyCancellation, announce, resume } = require('../services/noclass');
const { cleanSchedules, DAY_NAMES } = require('../services/classes');
const ST = ['P', 'A', 'L', 'E', 'N'];
const REASONS = ['Teacher unavailable', 'Meeting / training', 'Holiday / suspension', 'Bad weather', 'School activity', 'Other'];

module.exports = function mount(app, { sb, wrap, bad, teacherOnly, curYear }) {
  // The teacher must be assigned to this subject in this section (the adviser assigns them).
  const myClass = async (uid, section_id, subject_id) => {
    const { data } = await sb.from('section_subjects').select('teacher_id,sections(school_year_id,grade_level,name),subjects(code,name)').match({ section_id, subject_id }).maybeSingle();
    if (!data || data.teacher_id !== uid) throw bad('You are not assigned to this class', 403); return data;
  };
  const SCOLS = 'id,student_no,first_name,last_name,sex';
  const byName = (a, b) => String(b.sex || '').localeCompare(String(a.sex || '')) || String(a.last_name).localeCompare(String(b.last_name)) || String(a.first_name).localeCompare(String(b.first_name));
  // Everyone in the section, plus (when a subject is given) students from other sections who enrolled in that subject.
  const classStudents = async (section_id, subject_id) => {
    const base = (await sb.from('students').select(SCOLS).eq('section_id', section_id).eq('status', 'enrolled').order('sex', { ascending: false }).order('last_name').order('first_name')).data || [];
    if (!subject_id) return base;
    const { data: ex } = await sb.from('student_subjects').select('student_id').match({ section_id, subject_id });
    const have = new Set(base.map(x => x.id)), ids = (ex || []).map(x => x.student_id).filter(id => !have.has(id));
    if (!ids.length) return base;
    const { data: more } = await sb.from('students').select(SCOLS).in('id', ids).eq('status', 'enrolled');
    return [...base, ...(more || [])].sort(byName);
  };
  const lockedTerm = async (section_id, subject_id, term) => ((await sb.from('grades').select('id', { count: 'exact', head: true }).match({ section_id, subject_id, term, released: true })).count || 0) > 0;
  const checkDate = d => { if (!validDate(d) || d > phToday()) throw bad('Choose a valid date that is not in the future.'); if (!isWeekday(d)) throw bad('Classes are held Monday to Friday. Pick a weekday.'); };
  // ---- Offline queue support -------------------------------------------------------------------------------------
  // A change saved on a phone without internet is sent later with an operation id (X-Op-Id). The first request claims the id,
  // a retry of the same id returns the stored result instead of applying (and notifying) again. A claim stuck in "processing"
  // for 2 minutes (server restarted midway) can be taken over.
  const idem = (kind, fn) => wrap(async (q, r) => {
    const id = q.get('X-Op-Id'); if (!id) return fn(q, r);
    if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i.test(id)) throw bad('Bad operation id');
    const { error } = await sb.from('sync_ops').insert({ op_id: id, user_id: q.user.id, kind, status: 'processing' });
    if (error) {
      const { data: o } = await sb.from('sync_ops').select('*').eq('op_id', id).maybeSingle();
      if (o && o.user_id !== q.user.id) throw bad('Bad operation id', 403);
      if (o?.status === 'done') return r.json({ ...(o.result || {}), replayed: true });
      if (o && Date.now() - Date.parse(o.created_at) > 120000) await sb.from('sync_ops').update({ created_at: new Date().toISOString() }).eq('op_id', id);
      else throw bad('This change is already being processed. It will be retried.', 409);
    }
    let out = {};
    try { await fn(q, { json: x => { out = x; } }); }
    catch (e) { await sb.from('sync_ops').delete().eq('op_id', id); throw e; }        // not applied: let the retry run again
    await sb.from('sync_ops').update({ status: 'done', result: out }).eq('op_id', id);
    r.json(out);
  });
  const ts = v => (v == null ? null : Date.parse(v));                                    // versions are compared as instants (ms)



  // ---- Add / remove a class (a teacher teaching a subject in ANY section, advisory or not)
  const hhmm = t => String(t).slice(0, 5);
  // The teacher cannot be in two places at once, and a section cannot have two classes at the same time.
  const conflictCheck = async (teacher_id, section_id, slots) => {
    for (const x of slots) {
      const sel = 'start_time,end_time,sections(name,grade_level),subjects(name)';
      const { data: mine } = await sb.from('schedules').select(sel).eq('teacher_id', teacher_id).eq('day_of_week', x.day).lt('start_time', x.end).gt('end_time', x.start).limit(1);
      if (mine?.length) { const m = mine[0]; throw bad(`You already teach ${m.subjects?.name || 'a class'} (Grade ${m.sections?.grade_level} ${m.sections?.name}) on ${DAY_NAMES[x.day]} ${hhmm(m.start_time)}-${hhmm(m.end_time)}`, 409); }
      if (section_id) {
        const { data: sec } = await sb.from('schedules').select('start_time,end_time,subjects(name)').eq('section_id', section_id).eq('day_of_week', x.day).lt('start_time', x.end).gt('end_time', x.start).limit(1);
        if (sec?.length) throw bad(`That section already has ${sec[0].subjects?.name || 'a class'} on ${DAY_NAMES[x.day]} ${hhmm(sec[0].start_time)}-${hhmm(sec[0].end_time)}`, 409);
      }
    }
  };
  const insertSlots = (section_id, subject_id, teacher_id, slots, room) =>
    sb.from('schedules').insert(slots.map(x => ({ section_id, subject_id, teacher_id, day_of_week: x.day, start_time: x.start, end_time: x.end, room: x.room || room || null })));

  app.post('/api/classes', teacherOnly, wrap(async (q, r) => {
    const b = q.body || {}, y = await curYear();
    const { data: me } = await sb.from('teachers').select('grade_levels,first_name,last_name').eq('id', q.user.id).single();
    const grade = Number(b.grade_level);
    if (!me.grade_levels.includes(grade)) throw bad(`Grade ${b.grade_level || ''} is not one of your grade levels. Add it in Profile first.`);
    const advisoryOnly = b.advisory_only === true, wantAdviser = advisoryOnly || b.adviser === true;   // "I'm the adviser" / "I only advise this section"
    let mySub = null, slots = [];
    if (!advisoryOnly) {
      mySub = (await sb.from('teacher_subjects').select('code,name').eq('teacher_id', q.user.id).eq('code', String(b.subject_code || '').toUpperCase()).maybeSingle()).data;
      if (!mySub) throw bad('Choose one of your subjects. Add it in the Subjects tab first.');
      slots = cleanSchedules(b.schedules);
    }

    // section: reuse an existing one (same grade + section name OR room, any adviser) or create it
    let sec = null; const name = String(b.section_name || '').trim();
    if (b.section_id) {
      sec = (await sb.from('sections').select('*').eq('id', b.section_id).maybeSingle()).data;
      if (!sec || sec.grade_level !== grade || sec.school_year_id !== y.id) throw bad('That section does not match the grade level');
    } else {
      if (!name || name.length > 30) throw bad('Enter the section name (up to 30 characters)');
      const norm = v => String(v || '').trim().toLowerCase();
      const { data: inGrade } = await sb.from('sections').select('*').eq('school_year_id', y.id).eq('grade_level', grade);
      sec = (inGrade || []).find(x => norm(x.name) === norm(name) || (x.homeroom && norm(x.homeroom) === norm(name))) || null;
    }
    if (wantAdviser && sec?.adviser_id && sec.adviser_id !== q.user.id) {      // somebody else already advises this section
      const { data: a } = await sb.from('teacher_names').select('first_name,last_name').eq('id', sec.adviser_id).maybeSingle();
      throw bad(`Grade ${grade} ${sec.name} already has an adviser${a ? ` (${a.first_name} ${a.last_name})` : ''}.`, 409);
    }
    let sub = null;
    if (!advisoryOnly) {
      sub = (await sb.from('subjects').select('id,name').eq('code', mySub.code).maybeSingle()).data;
      if (!sub) { const ins = await sb.from('subjects').insert({ code: mySub.code, name: mySub.name }).select('id,name').single(); if (ins.error) throw ins.error; sub = ins.data; }
      if (sec) {
        const { data: ex } = await sb.from('section_subjects').select('teacher_id,teachers(first_name,last_name)').match({ section_id: sec.id, subject_id: sub.id }).maybeSingle();
        if (ex && ex.teacher_id !== q.user.id) throw bad(`${ex.teachers?.first_name} ${ex.teachers?.last_name} already teaches ${mySub.name} in this section`, 409);
      }
      await conflictCheck(q.user.id, sec?.id, slots);                         // nothing is written until every check passes
    }

    let created = false;
    if (!sec) {
      const { data: used } = await sb.from('sections').select('biometric_dept_no').not('biometric_dept_no', 'is', null);
      const taken = new Set((used || []).map(u => u.biometric_dept_no)); let dept = 1; while (taken.has(dept)) dept++;
      const ins = await sb.from('sections').insert({ school_year_id: y.id, grade_level: grade, name, adviser_id: wantAdviser ? q.user.id : null, homeroom: (b.room || '').trim() || null, biometric_dept_no: dept <= 16 ? dept : null }).select().single();
      if (ins.error) throw ins.error; sec = ins.data; created = true;
    } else if (wantAdviser && !sec.adviser_id) {
      const up = await sb.from('sections').update({ adviser_id: q.user.id }).eq('id', sec.id).is('adviser_id', null).select().single();
      if (up.error) throw bad('Someone just became the adviser of this section.', 409); sec = up.data;
    }
    const { count } = await sb.from('students').select('id', { count: 'exact', head: true }).eq('section_id', sec.id).eq('status', 'enrolled');
    const base = { section_id: sec.id, created_section: created, section_name: sec.name, grade_level: grade, grading_term: sec.grading_term || 1, students: count || 0, you_are_adviser: sec.adviser_id === q.user.id, has_adviser: !!sec.adviser_id };
    if (advisoryOnly) return r.json({ ...base, advisory_only: true });

    const { error: e1 } = await sb.from('section_subjects').upsert({ section_id: sec.id, subject_id: sub.id, teacher_id: q.user.id }, { onConflict: 'section_id,subject_id' }); if (e1) throw e1;
    const { error: e2 } = await insertSlots(sec.id, sub.id, q.user.id, slots, (b.room || '').trim() || sec.homeroom); if (e2) throw e2;
    if (sec.adviser_id && sec.adviser_id !== q.user.id) await notify(sb, [sec.adviser_id], { kind: 'section', title: 'New class in your section', body: `${me.first_name} ${me.last_name} will teach ${mySub.name} to Grade ${grade} ${sec.name}.` });
    r.json({ ...base, subject_id: sub.id, subject_name: mySub.name });
  }));

  app.post('/api/classes/:section_id/:subject_id/schedules', teacherOnly, wrap(async (q, r) => {
    const c = await myClass(q.user.id, q.params.section_id, q.params.subject_id);
    const slots = cleanSchedules(q.body.schedules); await conflictCheck(q.user.id, q.params.section_id, slots);
    const { data: sec } = await sb.from('sections').select('homeroom').eq('id', q.params.section_id).single();
    const { error } = await insertSlots(q.params.section_id, q.params.subject_id, q.user.id, slots, (q.body.room || '').trim() || sec?.homeroom); if (error) throw error;
    r.json({ added: slots.length });
  }));

  // Stop teaching a class. Grades, attendance and class-record data are kept; only the assignment and its schedule go.
  app.delete('/api/classes/:section_id/:subject_id', teacherOnly, wrap(async (q, r) => {
    await myClass(q.user.id, q.params.section_id, q.params.subject_id);
    await sb.from('schedules').delete().match({ section_id: q.params.section_id, subject_id: q.params.subject_id, teacher_id: q.user.id });
    await sb.from('section_subjects').delete().match({ section_id: q.params.section_id, subject_id: q.params.subject_id }); r.json({ ok: true });
  }));


  // Teachers who teach a subject in the section (they are the ones who can take over the advisory)
  const sectionTeachers = async (sectionId, except) => [...new Set(((await sb.from('section_subjects').select('teacher_id').eq('section_id', sectionId)).data || []).map(x => x.teacher_id).filter(t => t && t !== except))];
  const secLabel = async id => { const { data } = await sb.from('sections').select('grade_level,name').eq('id', id).maybeSingle(); return data ? `Grade ${data.grade_level} ${data.name}` : 'the section'; };
  const nameOf = async id => { const { data } = await sb.from('teacher_names').select('first_name,last_name').eq('id', id).maybeSingle(); return data ? `${data.first_name} ${data.last_name}`.trim() : 'A teacher'; };

  app.post('/api/sections/:id/claim', teacherOnly, wrap(async (q, r) => {                      // become the adviser of a section that has none
    const { data } = await sb.from('sections').update({ adviser_id: q.user.id }).eq('id', q.params.id).is('adviser_id', null).select('id');
    if (!data?.length) throw bad('This section already has an adviser.', 409);
    const [label, who] = await Promise.all([secLabel(q.params.id), nameOf(q.user.id)]);
    await notify(sb, await sectionTeachers(q.params.id, q.user.id), { kind: 'section', title: `${who} is now the adviser`, body: `${label} has a new adviser`, data: { section_id: q.params.id } }).catch(() => {});
    r.json({ ok: true });
  }));
  // The adviser steps down. The section stays; its subject teachers are told and one of them can take over.
  app.post('/api/sections/:id/leave', teacherOnly, wrap(async (q, r) => {
    const { data } = await sb.from('sections').update({ adviser_id: null }).eq('id', q.params.id).eq('adviser_id', q.user.id).select('id');
    if (!data?.length) throw bad('You are not the adviser of this section.', 403);
    const [label, who] = await Promise.all([secLabel(q.params.id), nameOf(q.user.id)]);
    await notify(sb, await sectionTeachers(q.params.id, q.user.id), { kind: 'section', title: `${label} needs an adviser`, body: `${who} left the advisory. Open the class and tap "Become adviser" to take over.`, data: { section_id: q.params.id } }).catch(() => {});
    r.json({ ok: true });
  }));

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
  app.post('/api/class-attendance', teacherOnly, idem('class_attendance', async (q, r) => {
    const { section_id, subject_id, dates } = q.body, queued = q.body.queued === true;   // dates: [{date, entries:[{student_id,status,remarks,base}]}]
    const c = await myClass(q.user.id, section_id, subject_id); const ok = new Set((await classStudents(section_id, subject_id)).map(s => s.id)); let n = 0;
    if (!dates?.length) throw bad('Nothing to save. Add a date column first.');
    const seen = new Set(); for (const d of dates) { checkDate(d.date); if (seen.has(d.date)) throw bad(`${d.date} appears twice. Keep one column per date.`); seen.add(d.date); }
    const skipped = [], versions = [], stamp = new Date().toISOString();
    for (const d of dates) {
      const base = new Map(d.entries.map(e => [e.student_id, e.base || null]));
      let rows = [];
      for (const e of d.entries) {
        if (!ok.has(e.student_id)) { if (queued) skipped.push({ student_id: e.student_id, date: d.date, reason: 'student_left' }); continue; }
        if (!ST.includes(e.status)) continue;
        rows.push({ student_id: e.student_id, section_id, subject_id, school_year_id: c.sections.school_year_id, att_date: d.date, status: e.status, remarks: (e.remarks || '').slice(0, 120) || null, marked_by: q.user.id, updated_at: stamp });
      }
      if (!rows.length) continue;
      const { data: old } = await sb.from('class_attendance').select('student_id,status,updated_at').match({ subject_id, att_date: d.date }).in('student_id', rows.map(x => x.student_id));
      const was = new Map((old || []).map(o => [o.student_id, o]));
      if (queued) {                                       // an offline edit never overwrites newer work and never brings back what was deleted
        rows = rows.filter(x => {
          const cur = was.get(x.student_id), b0 = base.get(x.student_id);
          if (cur && cur.status === x.status) { versions.push({ student_id: x.student_id, date: d.date, updated_at: cur.updated_at }); return false; }   // already the same: nothing to do
          if (cur && (b0 == null || ts(cur.updated_at) !== ts(b0))) { skipped.push({ student_id: x.student_id, date: d.date, reason: 'changed' }); return false; }   // someone changed it after you looked
          if (!cur && b0 != null) { skipped.push({ student_id: x.student_id, date: d.date, reason: 'deleted' }); return false; }                                  // it was deleted after you looked
          return true;
        });
        if (!rows.length) continue;
      }
      const { error } = await sb.from('class_attendance').upsert(rows, { onConflict: 'student_id,subject_id,att_date' }); if (error) throw error; n += rows.length;
      for (const x of rows) versions.push({ student_id: x.student_id, date: d.date, updated_at: stamp });
      const recent = d.date >= new Date(Date.now() + 8 * 36e5 - 2 * 864e5).toISOString().slice(0, 10);       // families hear only about recent days that changed
      const changed = rows.filter(x => ['A', 'L', 'E'].includes(x.status) && was.get(x.student_id)?.status !== x.status);
      if (recent && changed.length) {
        const ppl = await parentsOfMany(sb, changed.map(x => x.student_id)), byId = new Map((await classStudents(section_id, subject_id)).map(s => [s.id, s]));
        for (const x of changed) { const s = byId.get(x.student_id); if (!s) continue;
          await notify(sb, [s.id, ...(ppl.get(s.id) || [])], { kind: 'attendance', title: `${s.first_name} is ${x.status === 'A' ? 'absent' : x.status === 'L' ? 'late' : 'excused'} in ${c.subjects.name}`,
            body: `Marked by the subject teacher for ${d.date}.`, data: { student_id: s.id, date: d.date, status: x.status, subject_id } }); }
      }
    }
    r.json({ saved: n, skipped, versions, dropped: await applyStanding(section_id, subject_id, c) });
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

  // ---- No-class alerts: pick classes (any grade level / section), notify students + parents, mark everybody "No class" (not absent)
  app.post('/api/no-class', teacherOnly, wrap(async (q, r) => {
    const b = q.body || {}, today = phToday(), date = b.date || today;
    if (!validDate(date) || !isWeekday(date)) throw bad('Pick a valid weekday (Monday to Friday).');
    if (date < today) throw bad('Pick today or a later date.');
    if (date > new Date(Date.now() + 8 * 36e5 + 60 * 864e5).toISOString().slice(0, 10)) throw bad('That date is too far ahead.');
    const seen = new Set(), targets = (Array.isArray(b.targets) ? b.targets : []).filter(t => t?.section_id && t?.subject_id && !seen.has(t.section_id + t.subject_id) && seen.add(t.section_id + t.subject_id));
    if (!targets.length) throw bad('Choose at least one class.'); if (targets.length > 60) throw bad('Too many classes at once.');
    const reason = REASONS.includes(b.reason) ? b.reason : null, message = String(b.message || '').trim().slice(0, 140) || null;
    const out = { classes: 0, students: 0, notified: 0, skipped: 0 };
    for (const t of targets) {
      const c = await myClass(q.user.id, t.section_id, t.subject_id);
      const { data: ex } = await sb.from('class_cancellations').select('id').match({ section_id: t.section_id, subject_id: t.subject_id, cancel_date: date }).maybeSingle();
      if (ex) { out.skipped++; continue; }                                       // already announced: do not spam
      const row = { section_id: t.section_id, subject_id: t.subject_id, cancel_date: date, reason, message, label: `Grade ${c.sections.grade_level} · ${c.sections.name}`, subject_name: c.subjects.name, created_by: q.user.id };
      const { data: ins, error } = await sb.from('class_cancellations').insert(row).select().single(); if (error) throw error;
      out.students += date <= today ? await applyCancellation(sb, ins) : (await classStudents(t.section_id, t.subject_id)).length;
      out.notified += await announce(sb, ins); out.classes++;
    }
    r.json(out);
  }));
  app.delete('/api/no-class/:id', teacherOnly, wrap(async (q, r) => {          // "class is on after all"
    const { data: c } = await sb.from('class_cancellations').select('*').eq('id', q.params.id).maybeSingle();
    if (!c) throw bad('Notice not found', 404); await myClass(q.user.id, c.section_id, c.subject_id);
    r.json({ notified: await resume(sb, c) });
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

  app.put('/api/record/scores', teacherOnly, idem('record_scores', async (q, r) => {
    const { section_id, subject_id, term, scores } = q.body, queued = q.body.queued === true;   // scores: [{column_id, student_id, score|null, base}]
    const c = await myClass(q.user.id, section_id, subject_id);
    const { data: cols } = await sb.from('record_columns').select('id,max_score').match({ section_id, subject_id, term, school_year_id: c.sections.school_year_id, is_deleted: false });
    const max = new Map(cols.map(x => [x.id, +x.max_score])), studs = new Set((await classStudents(section_id, subject_id)).map(s => s.id));
    const skipped = [], versions = [], stamp = new Date().toISOString();
    let list = scores;
    if (!queued) {                                        // online: all or nothing, as before
      const bads = scores.filter(s => !max.has(s.column_id) || !studs.has(s.student_id) || (s.score != null && !(s.score >= 0 && s.score <= max.get(s.column_id))));
      if (bads.length) throw bad('Scores must be between 0 and the highest possible score. Nothing was saved.');
    } else {                                              // from the offline queue: apply what is still valid, report the rest
      list = [];
      for (const s of scores) {
        if (!max.has(s.column_id)) skipped.push({ column_id: s.column_id, student_id: s.student_id, reason: 'column_deleted' });           // a deleted column is never brought back
        else if (!studs.has(s.student_id)) skipped.push({ column_id: s.column_id, student_id: s.student_id, reason: 'student_left' });
        else if (s.score != null && !(s.score >= 0 && s.score <= max.get(s.column_id))) skipped.push({ column_id: s.column_id, student_id: s.student_id, reason: 'invalid' });
        else list.push(s);
      }
      const colIds = [...new Set(list.map(s => s.column_id))];
      const { data: cur } = colIds.length ? await sb.from('record_scores').select('column_id,student_id,score,updated_at').in('column_id', colIds) : { data: [] };
      const have = new Map((cur || []).map(x => [x.column_id + '|' + x.student_id, x]));
      list = list.filter(s => {
        const row = have.get(s.column_id + '|' + s.student_id), b0 = s.base || null, want = s.score == null ? null : Math.round(s.score * 100) / 100;
        if (!row && want == null) return false;                                                     // already empty
        if (row && want != null && +row.score === want) { versions.push({ column_id: s.column_id, student_id: s.student_id, updated_at: row.updated_at }); return false; }   // already that score
        if (row && (b0 == null || ts(row.updated_at) !== ts(b0))) { skipped.push({ column_id: s.column_id, student_id: s.student_id, reason: 'changed' }); return false; }
        if (!row && b0 != null) { skipped.push({ column_id: s.column_id, student_id: s.student_id, reason: 'deleted' }); return false; }     // cleared on the server after you looked
        return true;
      });
    }
    const sets = list.filter(s => s.score != null).map(s => ({ column_id: s.column_id, student_id: s.student_id, score: Math.round(s.score * 100) / 100, updated_at: stamp }));
    if (sets.length) { const { error } = await sb.from('record_scores').upsert(sets); if (error) throw error; for (const x of sets) versions.push({ column_id: x.column_id, student_id: x.student_id, updated_at: stamp }); }
    for (const s of list.filter(s => s.score == null)) await sb.from('record_scores').delete().match({ column_id: s.column_id, student_id: s.student_id });
    r.json({ changes: list.length, skipped, versions });
  }));
  app.post('/api/record/push-grade', teacherOnly, wrap(async (q, r) => {   // class record -> term grade (weighted %, optionally transmuted 60->75)
    const { section_id, subject_id, term, transmute: tr } = q.body; const c = await myClass(q.user.id, section_id, subject_id);
    if (await lockedTerm(section_id, subject_id, term)) throw bad(`Term ${term} grades are released. Unrelease them before editing.`);
    const yid = c.sections.school_year_id;
    const { data: cols } = await sb.from('record_columns').select('*').match({ section_id, subject_id, term, school_year_id: yid, is_deleted: false });
    const { data: sc } = cols.length ? await sb.from('record_scores').select('*').in('column_id', cols.map(x => x.id)) : { data: [] };
    const scores = {}; for (const s of sc) (scores[s.column_id] ||= {})[s.student_id] = +s.score;
    const rows = []; for (const s of await classStudents(section_id, subject_id)) { const p = recPercent(cols, scores, s.id); if (p == null) continue;
      rows.push({ student_id: s.id, subject_id, section_id, school_year_id: yid, term, grade: Math.round((tr ? transmute(p) : p) * 100) / 100, entered_by: q.user.id, updated_at: new Date().toISOString() }); }
    if (rows.length) { const { error } = await sb.from('grades').upsert(rows, { onConflict: 'student_id,subject_id,school_year_id,term' }); if (error) throw error; }
    r.json({ saved: rows.length });
  }));

  // ---- Grades: direct entry, release / unrelease (release notifies students + parents)
  app.post('/api/grades', teacherOnly, wrap(async (q, r) => {
    const { section_id, subject_id, term, grades } = q.body; const c = await myClass(q.user.id, section_id, subject_id);   // grades: [{student_id, grade|null}]
    if (await lockedTerm(section_id, subject_id, term)) throw bad(`Term ${term} grades are released. Unrelease them before editing.`);
    const studs = new Set((await classStudents(section_id, subject_id)).map(s => s.id));
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
