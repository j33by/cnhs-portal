const GRACE_MIN = 15;
const toMin = t => { const [h, m] = t.split(':'); return +h * 60 + +m; };
// scheduledStart 'HH:MM' (first class of that section that day) -> 'P' or 'L'.
function statusFor(timeIn, scheduledStart) {
  if (!scheduledStart) return 'P';
  return toMin(timeIn) > toMin(scheduledStart) + GRACE_MIN ? 'L' : 'P';
}
module.exports = { statusFor, GRACE_MIN };
