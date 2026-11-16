const assert = require('assert');
const R = require('./services/records'), B = require('./services/biometric');
const cols = [{ id: 'q1', max_score: 20, weight: 1 }, { id: 'p1', max_score: 100, weight: 2 }];
const sc = { q1: { s1: 15 }, p1: { s1: 90 } };
assert.strictEqual(+R.recPercent(cols, sc, 's1').toFixed(2), 85);          // (75*1 + 90*2)/3 = 85
assert.strictEqual(R.recPercent(cols, sc, 'nobody'), null);
assert.strictEqual(R.transmute(60), 75); assert.strictEqual(R.transmute(100), 100); assert.strictEqual(R.transmute(0), 60);
assert.deepStrictEqual(['ok', 'warning', 'dropped'], [R.standingOf(7, 10), R.standingOf(8, 10), R.standingOf(11, 10)]);
assert.strictEqual(R.honorLabel(95, true), 'With High Honors');
assert.ok(R.isWeekday('2026-11-13') && !R.isWeekday('2026-11-14'));
assert.strictEqual(B.summarizeTimes(['14:19:32', '14:23:11']).time_out, null);          // double tap, not "left"
assert.strictEqual(B.summarizeTimes(['14:19:32', '15:20:02']).time_out, '15:20:02');
console.log('all record/biometric tests passed');
// ---- profile validation
const { cleanProfile } = require('./services/profile');
const throws = (fn, re) => { try { fn(); } catch (e) { assert.ok(re.test(e.message), e.message); return; } assert.fail('expected an error'); };
assert.deepStrictEqual(cleanProfile('student', { first_name: ' Ana ', age: '15', sex: 'F', birthdate: '2011-03-02', lrn: '' }), { first_name: 'Ana', age: 15, sex: 'F', birthdate: '2011-03-02', lrn: null });
throws(() => cleanProfile('student', { age: 'abc' }), /Age/);
throws(() => cleanProfile('student', { first_name: '  ' }), /required/);
throws(() => cleanProfile('student', { birthdate: '2011/3/2' }), /Birthdate/);
assert.deepStrictEqual(cleanProfile('student', { student_no: 'HACK', biometric_id: 9, section_id: 'x' }), {});          // IDs / section cannot be edited
throws(() => cleanProfile('teacher', { grade_levels: [7, 7] }), /grade levels/);
throws(() => cleanProfile('teacher', { grade_levels: [] }), /grade levels/);
assert.deepStrictEqual(cleanProfile('teacher', { grade_levels: [8, 7], teacher_no: 'T-1' }), { grade_levels: [8, 7] });
assert.deepStrictEqual(cleanProfile('parent', { full_name: 'Mama Ana', contact_no: '0917' }), { full_name: 'Mama Ana', contact_no: '0917' });
console.log('profile validation tests passed');
// ---- add-class schedule validation
const { cleanSchedules } = require('./services/classes');
assert.strictEqual(cleanSchedules([{ days: [1, 3, 5], start_time: '07:30', end_time: '08:30' }]).length, 3);
throws(() => cleanSchedules([]), /at least one/);
throws(() => cleanSchedules([{ days: [], start_time: '07:30', end_time: '08:30' }]), /days/);
throws(() => cleanSchedules([{ days: [7], start_time: '07:30', end_time: '08:30' }]), /days/);
throws(() => cleanSchedules([{ days: [1], start_time: '09:00', end_time: '08:00' }]), /after/);
throws(() => cleanSchedules([{ days: [1], start_time: '', end_time: '08:00' }]), /start and an end time/);
throws(() => cleanSchedules([{ days: [1], start_time: '07:00', end_time: '08:00' }, { days: [1, 2], start_time: '07:30', end_time: '08:30' }]), /overlap/);
assert.strictEqual(cleanSchedules([{ days: [1], start_time: '07:00', end_time: '08:00' }, { days: [1], start_time: '08:00', end_time: '09:00' }]).length, 2);   // back-to-back is fine
throws(() => cleanSchedules([{ days: [6], start_time: '07:30', end_time: '08:30' }]), /days/);   // classes are Monday to Friday
console.log('add-class validation tests passed');
// ---- schedule slots
const { parseSlots, findConflicts } = require('./services/slots');
assert.strictEqual(parseSlots([{ days: [1, 3], start: '08:00', end: '09:00' }, { days: [5], start: '10:00', end: '11:30' }]).length, 3);
throws(() => parseSlots([]), /time slots/);
throws(() => parseSlots([{ days: [], start: '08:00', end: '09:00' }]), /days/);
throws(() => parseSlots([{ days: [6], start: '08:00', end: '09:00' }]), /days/);
throws(() => parseSlots([{ days: [1], start: '09:00', end: '08:00' }]), /before its end/);
throws(() => parseSlots([{ days: [1], start: '8:00', end: '09:00' }]), /start time/);
throws(() => parseSlots([{ days: [1], start: '08:00', end: '09:00' }, { days: [1, 2], start: '08:30', end: '09:30' }]), /overlap/);
const fake = rows => ({ from: () => ({ select: () => ({ or: async () => ({ data: rows }) }) }) });
(async () => {
  const mine = { day_of_week: 1, start_time: '08:00:00', end_time: '09:00:00', teacher_id: 'T1', subjects: { name: 'Science' }, sections: { name: 'Rizal', grade_level: 7 } };
  assert.match(await findConflicts(fake([mine]), { teacherId: 'T1', sectionId: 'S9', rows: [{ day_of_week: 1, start: '08:30', end: '09:30' }] }), /you already teach: Science/);
  assert.match(await findConflicts(fake([{ ...mine, teacher_id: 'T2' }]), { teacherId: 'T1', sectionId: 'S9', rows: [{ day_of_week: 1, start: '08:30', end: '09:30' }] }), /already used in this section/);
  assert.strictEqual(await findConflicts(fake([mine]), { teacherId: 'T1', sectionId: 'S9', rows: [{ day_of_week: 1, start: '09:00', end: '10:00' }] }), null);   // back-to-back is fine
  assert.strictEqual(await findConflicts(fake([mine]), { teacherId: 'T1', sectionId: 'S9', rows: [{ day_of_week: 2, start: '08:00', end: '09:00' }] }), null);
  console.log('schedule slot tests passed');
})();
// ---- class reminders
const { dueReminders } = require('./services/reminders');
(() => {
  const at = (h, m, dow = 1) => new Date(Date.UTC(2026, 10, 1 + dow, h, m));          // 2026-11-02 is a Monday: fields read as PH local time
  const teachers = new Map([['T1', { alert_minutes: 10 }], ['T2', { alert_minutes: 0 }]]);
  const slot = (o = {}) => ({ id: 's1', teacher_id: 'T1', day_of_week: 1, start_time: '08:00:00', ...o });
  assert.strictEqual(dueReminders({ slots: [slot()], teachers, now: at(7, 52) })[0].minutes, 8);   // 8 minutes before
  assert.strictEqual(dueReminders({ slots: [slot()], teachers, now: at(7, 50) })[0].minutes, 10);  // exactly at the lead time
  assert.strictEqual(dueReminders({ slots: [slot()], teachers, now: at(7, 49) }).length, 0);       // too early
  assert.strictEqual(dueReminders({ slots: [slot()], teachers, now: at(8, 0) }).length, 0);        // already started
  assert.strictEqual(dueReminders({ slots: [slot({ teacher_id: 'T2' })], teachers, now: at(7, 55) }).length, 0);   // reminders off
  assert.strictEqual(dueReminders({ slots: [slot({ day_of_week: 2 })], teachers, now: at(7, 55) }).length, 0);    // other day
  throws(() => cleanProfile('teacher', { alert_minutes: 7 }), /minutes/);
  assert.deepStrictEqual(cleanProfile('teacher', { alert_minutes: 15 }), { alert_minutes: 15 });
  console.log('class reminder tests passed');
})();
