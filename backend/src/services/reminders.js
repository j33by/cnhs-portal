// "Your class starts in N minutes" phone notifications for teachers.
const { notify } = require('./notify');
const phNow = (d = new Date()) => new Date(d.getTime() + 8 * 36e5);            // a Date whose UTC fields read as Philippine local time
const toMin = t => { const [h, m] = String(t).split(':'); return +h * 60 + +m; };
const t12 = t => { const [h, m] = String(t).split(':'); const H = +h; return `${H % 12 || 12}:${m} ${H >= 12 ? 'PM' : 'AM'}`; };

// Pure: which slots are inside their teacher's reminder window right now?  (class not started yet, starts within alert_minutes)
function dueReminders({ slots, teachers, now }) {
  const dow = now.getUTCDay(), min = now.getUTCHours() * 60 + now.getUTCMinutes(), out = [];
  for (const s of slots) {
    if (s.day_of_week !== dow) continue;
    const t = teachers.get(s.teacher_id); if (!t || !t.alert_minutes) continue;
    const left = toMin(s.start_time) - min;
    if (left > 0 && left <= t.alert_minutes) out.push({ slot: s, minutes: left });
  }
  return out;
}

async function sendClassReminders(sb, real = new Date()) {
  const now = phNow(real), date = now.toISOString().slice(0, 10), dow = now.getUTCDay();
  if (dow < 1 || dow > 5) return { sent: 0 };
  const { data: slots } = await sb.from('schedules').select('id,teacher_id,day_of_week,start_time,room,subjects(name),sections(name,grade_level)').eq('day_of_week', dow).not('teacher_id', 'is', null);
  if (!slots?.length) return { sent: 0 };
  const { data: ts } = await sb.from('teachers').select('id,alert_minutes').in('id', [...new Set(slots.map(s => s.teacher_id))]);
  const due = dueReminders({ slots, teachers: new Map((ts || []).map(t => [t.id, t])), now });
  let sent = 0;
  for (const d of due) {
    const { data: fresh } = await sb.from('class_reminders_sent').upsert({ schedule_id: d.slot.id, rdate: date }, { onConflict: 'schedule_id,rdate', ignoreDuplicates: true }).select();
    if (!fresh?.length) continue;                                                // already sent today
    const s = d.slot;
    await notify(sb, [s.teacher_id], { kind: 'class', title: `${s.subjects?.name || 'Class'} starts in ${d.minutes} min`,
      body: `Grade ${s.sections?.grade_level} ${s.sections?.name} · ${t12(s.start_time)}${s.room ? ' · ' + s.room : ''}`, data: { schedule_id: s.id } });
    sent++;
  }
  return { sent };
}
module.exports = { dueReminders, sendClassReminders };
