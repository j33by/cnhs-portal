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
