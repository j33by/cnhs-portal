const { parseLogs, summarizeTimes } = require('./biometric');
const { statusFor } = require('./status');
const { notify } = require('./notify');
const { isWeekday, phToday } = require('./records');
const t12 = t => { let [h, m] = t.split(':'); h = +h; return `${h % 12 || 12}:${m} ${h >= 12 ? 'PM' : 'AM'}`; };
const phParts = ts => { const d = new Date(new Date(ts).getTime() + 8 * 36e5).toISOString(); return { date: d.slice(0, 10), time: d.slice(11, 19) }; };
const daysAgo = (date, n) => new Date(Date.now() + 8 * 36e5 - n * 864e5).toISOString().slice(0, 10) <= date;   // within last n days
const parentsOf = async (sb, sid) => (await sb.from('parent_links').select('parent_id').eq('student_id', sid).eq('status', 'approved')).data?.map(l => l.parent_id) || [];

// Recompute one student's day from ALL stored punches (not just this file), then notify if something new happened.
async function recomputeDay(sb, stu, bio, date, { notifyUsers = true } = {}) {
  const { data: rows } = await sb.from('attendance').select('punched_at').eq('biometric_id', bio)
    .gte('punched_at', `${date}T00:00:00+08:00`).lte('punched_at', `${date}T23:59:59+08:00`);
  if (!rows?.length) return;
  const d = summarizeTimes(rows.map(r => phParts(r.punched_at).time));
  const dow = new Date(date + 'T00:00:00Z').getUTCDay();
  const { data: first } = await sb.from('schedules').select('start_time').eq('section_id', stu.section_id).eq('day_of_week', dow).order('start_time').limit(1);
  const bio_status = statusFor(d.time_in, first?.[0]?.start_time?.slice(0, 5));
  const { data: old } = await sb.from('daily_attendance').select('time_in,time_out,status,source').eq('student_id', stu.id).eq('att_date', date).maybeSingle();
  const keep = old?.source === 'manual';                                    // the teacher's decision wins; times still fill in
  const status = keep ? old.status : bio_status;
  await sb.from('daily_attendance').upsert({ student_id: stu.id, section_id: stu.section_id, att_date: date, status,
    time_in: d.time_in, time_out: d.time_out, punches: d.punches, ...(keep ? {} : { source: 'biometric' }) }, { onConflict: 'student_id,att_date' });
  if (!notifyUsers || !daysAgo(date, 2)) return;                            // old backfill stays silent
  const who = [stu.id, ...await parentsOf(sb, stu.id)], data = { student_id: stu.id, date, status };
  if (!old?.time_in) await notify(sb, who, { kind: 'attendance', title: status === 'L' ? `${stu.first_name} arrived late` : status === 'A' ? `${stu.first_name} is marked absent` : `${stu.first_name} is present`,
    body: `Time in ${t12(d.time_in)}${stu.sections?.name ? ' · ' + stu.sections.name : ''}`, data });
  else if (d.time_out && d.time_out !== old.time_out) await notify(sb, who, { kind: 'attendance', title: `${stu.first_name} left school`, body: `Time out ${t12(d.time_out)}`, data });
}

async function ingestLogs(sb, text) {
  const punches = parseLogs(text);
  if (!punches.length) return { punches: 0, newPunches: 0, notified: 0 };
  // remember everyone who exists on the terminal so their device IDs are never handed to a new student
  const names = new Map(); for (const p of punches) if (p.name) names.set(p.biometric_id, p.name);
  await sb.from('device_people').upsert([...new Set(punches.map(p => p.biometric_id))].map(id => ({ biometric_id: id, last_seen: new Date().toISOString(), ...(names.has(id) ? { name: names.get(id) } : {}) })), { onConflict: 'biometric_id' });

  const [{ data: stu }, { data: tea }] = await Promise.all([sb.from('students').select('id,biometric_id,first_name,section_id,sections(name)').not('biometric_id', 'is', null), sb.from('teachers').select('id,biometric_id').not('biometric_id', 'is', null)]);
  const sMap = new Map(stu.map(s => [s.biometric_id, s])), tMap = new Map(tea.map(t => [t.biometric_id, t.id]));
  const rows = punches.map(p => ({ biometric_id: p.biometric_id, device_id: p.device_id, punched_at: `${p.date}T${p.time}+08:00`, student_id: sMap.get(p.biometric_id)?.id || null, teacher_id: tMap.get(p.biometric_id) || null, _date: p.date }));
  const fresh = [];
  for (let i = 0; i < rows.length; i += 500) {                              // insert only unseen punches; .select() returns just the inserted ones
    const chunk = rows.slice(i, i + 500).map(({ _date, ...r }) => r);
    const { data, error } = await sb.from('attendance').upsert(chunk, { onConflict: 'biometric_id,punched_at', ignoreDuplicates: true }).select('biometric_id,punched_at');
    if (error) throw error; fresh.push(...(data || []));
  }
  const touched = new Set(fresh.map(r => r.biometric_id + '|' + phParts(r.punched_at).date));
  for (const k of touched) { const [bio, date] = k.split('|'); const s = sMap.get(+bio); if (s) await recomputeDay(sb, s, +bio, date); }

  // Days strictly before the newest punched day are complete -> mark no-shows absent. Today is closed by hand.
  const dates = [...new Set(punches.map(p => p.date))].sort(), last = dates[dates.length - 1]; let absent = 0;
  for (const d of dates.filter(d => d < last)) absent += (await closeDay(sb, d)).absent;
  await sb.from('usb_sync_state').update({ last_ingest: new Date().toISOString() }).eq('id', 1);
  return { punches: punches.length, newPunches: fresh.length, daysUpdated: touched.size, absentMarked: absent };
}

// Students whose section has class that weekday and who have no record for the date -> Absent.
async function closeDay(sb, date) {
  if (!isWeekday(date)) return { absent: 0 };
  const dow = new Date(date + 'T00:00:00Z').getUTCDay();
  const { data: scheds } = await sb.from('schedules').select('section_id').eq('day_of_week', dow);
  const secIds = [...new Set((scheds || []).map(s => s.section_id))]; if (!secIds.length) return { absent: 0 };
  const [{ data: stu }, { data: have }] = await Promise.all([sb.from('students').select('id,first_name,section_id,created_at').in('section_id', secIds).eq('status', 'enrolled'), sb.from('daily_attendance').select('student_id').eq('att_date', date)]);
  const got = new Set((have || []).map(h => h.student_id)); let absent = 0;
  for (const s of (stu || []).filter(s => !got.has(s.id) && s.created_at.slice(0, 10) <= date)) {
    await sb.from('daily_attendance').upsert({ student_id: s.id, section_id: s.section_id, att_date: date, status: 'A', punches: 0, source: 'biometric' }, { onConflict: 'student_id,att_date' });
    if (daysAgo(date, 2)) await notify(sb, [s.id, ...await parentsOf(sb, s.id)], { kind: 'attendance', title: `${s.first_name} is absent`, body: `No time-in recorded on ${date}.`, data: { student_id: s.id, date, status: 'A' } });
    absent++;
  }
  return { absent };
}

// A device ID was just linked to a student: attach old punches and rebuild their days (silently).
async function relinkPunches(sb, stu, bio) {
  await sb.from('attendance').update({ student_id: stu.id }).eq('biometric_id', bio).is('student_id', null);
  const { data } = await sb.from('attendance').select('punched_at').eq('biometric_id', bio);
  for (const date of new Set((data || []).map(r => phParts(r.punched_at).date))) await recomputeDay(sb, stu, bio, date, { notifyUsers: false });
}
module.exports = { ingestLogs, closeDay, relinkPunches, parentsOf };
