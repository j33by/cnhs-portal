const { parseLogs, dailyFromPunches } = require('./biometric');
const { statusFor } = require('./status');
const { notify } = require('./notify');
const t12 = t => { let [h, m] = t.split(':'); h = +h; return `${h % 12 || 12}:${m} ${h >= 12 ? 'PM' : 'AM'}`; };

// Ingest the USB log: store raw punches, derive daily status, notify students + approved parents.
async function ingestLogs(sb, text) {
  const punches = parseLogs(text);
  const { data: stu } = await sb.from('students').select('id,biometric_id,first_name,section_id,sections(name)');
  const { data: tea } = await sb.from('teachers').select('id,biometric_id');
  const sMap = new Map((stu || []).map(s => [s.biometric_id, s])), tMap = new Map((tea || []).map(t => [t.biometric_id, t.id]));
  const rows = punches.map(p => ({ biometric_id: p.biometric_id, device_id: p.device_id, punched_at: `${p.date}T${p.time}+08:00`,
    student_id: sMap.get(p.biometric_id)?.id || null, teacher_id: tMap.get(p.biometric_id) || null }));
  // only rows we haven't seen -> only those trigger notifications
  const { data: before } = await sb.from('attendance').select('biometric_id,punched_at');
  const seen = new Set((before || []).map(r => r.biometric_id + '|' + new Date(r.punched_at).getTime()));
  const fresh = rows.filter(r => !seen.has(r.biometric_id + '|' + new Date(r.punched_at).getTime()));
  if (fresh.length) await sb.from('attendance').upsert(rows, { onConflict: 'biometric_id,punched_at', ignoreDuplicates: true });

  const touched = new Set(fresh.filter(r => r.student_id).map(r => r.biometric_id + '|' + r.punched_at.slice(0, 10)));
  let notified = 0;
  for (const d of dailyFromPunches(punches)) {
    const s = sMap.get(d.biometric_id); if (!s || !touched.has(d.biometric_id + '|' + d.date)) continue;
    const dow = new Date(d.date + 'T00:00:00+08:00').getDay();
    const { data: first } = await sb.from('schedules').select('start_time').eq('section_id', s.section_id).eq('day_of_week', dow).order('start_time').limit(1);
    const status = statusFor(d.time_in, first?.[0]?.start_time?.slice(0, 5));
    const { data: old } = await sb.from('daily_attendance').select('time_in,time_out,status').eq('student_id', s.id).eq('att_date', d.date).maybeSingle();
    await sb.from('daily_attendance').upsert({ student_id: s.id, section_id: s.section_id, att_date: d.date, status: old?.status === 'E' ? 'E' : status,
      time_in: d.time_in, time_out: d.time_out, punches: d.punches }, { onConflict: 'student_id,att_date' });
    const { data: links } = await sb.from('parent_links').select('parent_id').eq('student_id', s.id).eq('status', 'approved');
    const who = [s.id, ...(links || []).map(l => l.parent_id)];
    if (!old || !old.time_in) { await notify(sb, who, { kind: 'attendance',
        title: status === 'L' ? `${s.first_name} arrived late` : `${s.first_name} is present`,
        body: `Time in ${t12(d.time_in)}${s.sections?.name ? ' · ' + s.sections.name : ''}`, data: { student_id: s.id, date: d.date, status } }); notified++; }
    else if (d.time_out && d.time_out !== old.time_out) { await notify(sb, who, { kind: 'attendance',
        title: `${s.first_name} left school`, body: `Time out ${t12(d.time_out)}`, data: { student_id: s.id, date: d.date } }); notified++; }
  }
  await sb.from('usb_sync_state').update({ last_ingest: new Date().toISOString() }).eq('id', 1);
  return { punches: punches.length, newPunches: fresh.length, notified };
}

// End of day: students of a section with a class today and no punch -> Absent, notify parents.
async function closeDay(sb, date) {
  const dow = new Date(date + 'T00:00:00+08:00').getDay();
  const { data: scheds } = await sb.from('schedules').select('section_id').eq('day_of_week', dow);
  const secIds = [...new Set((scheds || []).map(s => s.section_id))]; let absent = 0;
  if (!secIds.length) return { absent };
  const { data: stu } = await sb.from('students').select('id,first_name,section_id').in('section_id', secIds).eq('status', 'enrolled');
  const { data: have } = await sb.from('daily_attendance').select('student_id').eq('att_date', date);
  const got = new Set((have || []).map(h => h.student_id));
  for (const s of (stu || []).filter(s => !got.has(s.id))) {
    await sb.from('daily_attendance').upsert({ student_id: s.id, section_id: s.section_id, att_date: date, status: 'A', punches: 0 }, { onConflict: 'student_id,att_date' });
    const { data: links } = await sb.from('parent_links').select('parent_id').eq('student_id', s.id).eq('status', 'approved');
    await notify(sb, [s.id, ...(links || []).map(l => l.parent_id)], { kind: 'attendance', title: `${s.first_name} is absent`, body: `No biometric time-in recorded on ${date}.`, data: { student_id: s.id, date, status: 'A' } });
    absent++;
  }
  return { absent };
}
module.exports = { ingestLogs, closeDay };
