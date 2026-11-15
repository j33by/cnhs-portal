// Validation for the schedule part of "Add class".
const bad = m => Object.assign(new Error(m), { status: 400 });
const TIME = /^([01]\d|2[0-3]):[0-5]\d$/;
const DAY_NAMES = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];

// blocks: [{days:[1,3,5], start_time:'07:30', end_time:'08:30', room?}]  ->  one slot per day
function cleanSchedules(list) {
  if (!Array.isArray(list) || !list.length) throw bad('Add at least one schedule');
  const slots = [];
  for (const b of list) {
    const days = [...new Set(b?.days || [])];
    if (!days.length || days.some(d => !Number.isInteger(d) || d < 1 || d > 5)) throw bad('Pick the days (Monday to Friday) for every schedule');
    if (!TIME.test(b.start_time || '') || !TIME.test(b.end_time || '')) throw bad('Choose a start and an end time for every schedule');
    if (b.start_time >= b.end_time) throw bad('End time must be after start time');
    const room = b.room ? String(b.room).trim().slice(0, 30) || null : null;
    for (const d of days) slots.push({ day: d, start: b.start_time, end: b.end_time, room });
  }
  if (slots.length > 18) throw bad('Too many schedule slots');
  for (let i = 0; i < slots.length; i++) for (let j = i + 1; j < slots.length; j++) {
    const a = slots[i], c = slots[j];
    if (a.day === c.day && a.start < c.end && c.start < a.end) throw bad(`Two of your schedules overlap on ${DAY_NAMES[a.day]}`);
  }
  return slots;
}
module.exports = { cleanSchedules, DAY_NAMES };
