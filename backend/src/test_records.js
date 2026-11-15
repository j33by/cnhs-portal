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
