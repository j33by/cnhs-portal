// Pure functions ported 1:1 from the PHP portal (admin/inc/lib.php) so server and app agree.
const MAX_RECORD_COLS = 15;
const recPercent = (cols, scores, sid) => {          // scores[colId][studentId]
  let num = 0, den = 0;
  for (const c of cols) { const v = scores[c.id]?.[sid]; if (v == null) continue; num += (v / +c.max_score * 100) * +c.weight; den += +c.weight; }
  return den > 0 ? num / den : null;
};
const transmute = p => p >= 60 ? 75 + (p - 60) * 25 / 40 : 60 + p * 15 / 60;
const standingOf = (abs, free) => { free = Math.max(1, free); return abs > free ? 'dropped' : abs * 5 >= free * 4 ? 'warning' : 'ok'; };
const honorLabel = (avg, noFail) => !noFail ? '' : avg >= 98 ? 'With Highest Honors' : avg >= 95 ? 'With High Honors' : avg >= 90 ? 'With Honors' : '';
const isWeekday = d => { const n = new Date(d + 'T00:00:00Z').getUTCDay(); return n >= 1 && n <= 5; };
const phToday = () => new Date(Date.now() + 8 * 36e5).toISOString().slice(0, 10);
const validDate = d => /^\d{4}-\d{2}-\d{2}$/.test(d) && !isNaN(Date.parse(d));
module.exports = { MAX_RECORD_COLS, recPercent, transmute, standingOf, honorLabel, isWeekday, phToday, validDate };
