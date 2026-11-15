// Schedule slots: validation and double-booking checks shared by "New class", "Add time" and the adviser's schedule screen.
const DAY = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const HHMM = /^([01]\d|2[0-3]):[0-5]\d$/;
const bad = (m, s = 400) => Object.assign(new Error(m), { status: s });

// slots: [{days:[1,3], start:'08:00', end:'09:00'}]  ->  one row per day
function parseSlots(slots) {
  if (!Array.isArray(slots) || slots.length < 1 || slots.length > 8) throw bad('Add 1 to 8 time slots');
  const rows = [];
  for (const s of slots) {
    const days = [...new Set(s?.days || [])];
    if (!days.length || days.some(d => !Number.isInteger(d) || d < 1 || d > 5)) throw bad('Pick the days (Monday to Friday) for every time slot');
    if (!HHMM.test(s.start) || !HHMM.test(s.end) || s.start >= s.end) throw bad('Each time slot needs a start time that is before its end time');
    for (const d of days) rows.push({ day_of_week: d, start: s.start, end: s.end });
  }
  for (let i = 0; i < rows.length; i++) for (let j = i + 1; j < rows.length; j++) {
    const a = rows[i], b = rows[j];
    if (a.day_of_week === b.day_of_week && a.start < b.end && b.start < a.end) throw bad(`Two of your time slots overlap on ${DAY[a.day_of_week]}`);
  }
  return rows;
}

// Returns a readable message for the first clash with this teacher's other classes or with the section's timetable, else null.
async function findConflicts(sb, { teacherId, sectionId, rows }) {
  const parts = []; if (teacherId) parts.push(`teacher_id.eq.${teacherId}`); if (sectionId) parts.push(`section_id.eq.${sectionId}`);
  if (!parts.length) return null;
  const { data } = await sb.from('schedules').select('day_of_week,start_time,end_time,teacher_id,subjects(name),sections(name,grade_level)').or(parts.join(','));
  for (const n of rows) for (const o of data || []) {
    const os = o.start_time.slice(0, 5), oe = o.end_time.slice(0, 5);
    if (o.day_of_week !== n.day_of_week || !(n.start < oe && os < n.end)) continue;
    const what = `${o.subjects?.name || 'a class'} (Grade ${o.sections?.grade_level} ${o.sections?.name})`;
    return o.teacher_id === teacherId
      ? `${DAY[n.day_of_week]} ${n.start}-${n.end} overlaps a class you already teach: ${what}, ${os}-${oe}.`
      : `${DAY[n.day_of_week]} ${n.start}-${n.end} is already used in this section by ${what}, ${os}-${oe}.`;
  }
  return null;
}
module.exports = { parseSlots, findConflicts, DAY };
