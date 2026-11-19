// "No class" notices: tell students + parents, and mark every student's subject attendance as N (No class) so nobody is absent.
const { notify } = require('./notify');
const { parentsOfMany } = require('./attendance');
const { phToday } = require('./records');

const pretty = date => {
  const today = phToday(), tomorrow = new Date(new Date(today + 'T00:00:00Z').getTime() + 864e5).toISOString().slice(0, 10);
  const d = new Date(date + 'T00:00:00Z').toLocaleDateString('en-US', { weekday: 'long', month: 'short', day: 'numeric', timeZone: 'UTC' });
  return date === today ? `today (${d})` : date === tomorrow ? `tomorrow (${d})` : d;
};
const enrolled = async (sb, section_id, subject_id) => {                          // the section + students of other sections who enrolled in this subject
  const base = (await sb.from('students').select('id,first_name').eq('section_id', section_id).eq('status', 'enrolled')).data || [];
  const { data: ex } = await sb.from('student_subjects').select('student_id').match({ section_id, subject_id });
  const have = new Set(base.map(x => x.id)), ids = (ex || []).map(x => x.student_id).filter(id => !have.has(id));
  if (!ids.length) return base;
  return [...base, ...((await sb.from('students').select('id,first_name').in('id', ids).eq('status', 'enrolled')).data || [])];
};

// Writes the N marks. Only used for today or past dates (future dates are applied on the day itself by applyDueCancellations).
async function applyCancellation(sb, c) {
  const { data: yr } = await sb.from('school_years').select('id').eq('is_current', true).single();
  const studs = await enrolled(sb, c.section_id, c.subject_id);
  const rows = studs.map(s => ({ student_id: s.id, section_id: c.section_id, subject_id: c.subject_id, school_year_id: yr.id, att_date: c.cancel_date,
    status: 'N', remarks: (c.reason || 'No class').slice(0, 120), source: 'no_class', marked_by: c.created_by, updated_at: new Date().toISOString() }));
  for (let i = 0; i < rows.length; i += 200) { const { error } = await sb.from('class_attendance').upsert(rows.slice(i, i + 200), { onConflict: 'student_id,subject_id,att_date' }); if (error) throw error; }
  await sb.from('class_cancellations').update({ applied: true, students: studs.length }).eq('id', c.id);
  return studs.length;
}

// Notices created for a future day get their N marks once that day arrives.
async function applyDueCancellations(sb) {
  const { data } = await sb.from('class_cancellations').select('*').eq('applied', false).lte('cancel_date', phToday());
  let n = 0; for (const c of data || []) { await applyCancellation(sb, c); n++; }
  return { appliedNotices: n };
}

async function announce(sb, c) {                                    // c: cancellation row. Returns how many people were notified.
  const studs = await enrolled(sb, c.section_id, c.subject_id), parents = await parentsOfMany(sb, studs.map(s => s.id));
  const why = [c.reason, c.message].filter(Boolean).join(' · '), when = pretty(c.cancel_date); let people = 0;
  await notify(sb, studs.map(s => s.id), { kind: 'no_class', title: `No ${c.subject_name} class`, body: `${c.label}: no class ${when}.${why ? ' ' + why + '.' : ''} You will not be marked absent.`, data: { subject_id: c.subject_id, section_id: c.section_id, date: c.cancel_date } });
  people += studs.length;
  for (const s of studs) { const p = parents.get(s.id) || []; if (!p.length) continue;
    await notify(sb, p, { kind: 'no_class', title: `No ${c.subject_name} class for ${s.first_name}`, body: `${c.label}: no class ${when}.${why ? ' ' + why + '.' : ''} ${s.first_name} will not be marked absent.`, data: { student_id: s.id, subject_id: c.subject_id, date: c.cancel_date } });
    people += p.length; }
  return people;
}

async function resume(sb, c) {                                      // teacher changed their mind: class is on again
  await sb.from('class_attendance').delete().match({ section_id: c.section_id, subject_id: c.subject_id, att_date: c.cancel_date, status: 'N' });
  await sb.from('class_cancellations').delete().eq('id', c.id);
  if (c.cancel_date < phToday()) return 0;
  const studs = await enrolled(sb, c.section_id, c.subject_id), parents = await parentsOfMany(sb, studs.map(s => s.id));
  await notify(sb, [...studs.map(s => s.id), ...[...parents.values()].flat()], { kind: 'no_class', title: `${c.subject_name} class is back on`, body: `${c.label}: the no-class notice for ${pretty(c.cancel_date)} was cancelled. Class will proceed as scheduled.`, data: { subject_id: c.subject_id, date: c.cancel_date } });
  return studs.length;
}
module.exports = { applyCancellation, applyDueCancellations, announce, resume, pretty };
