// Same formulas as the PHP portal and backend/src/services/records.js
double? recPercent(List<Map<String, dynamic>> cols, Map<String, Map<String, double>> scores, String sid) {
  double acc = 0, den = 0;
  for (final c in cols) {
    final v = scores[c['id']]?[sid];
    if (v == null) continue;
    final w = (c['weight'] as num).toDouble();
    acc += v / (c['max_score'] as num).toDouble() * 100 * w;
    den += w;
  }
  return den > 0 ? acc / den : null;
}
double transmute(double p) => p >= 60 ? 75 + (p - 60) * 25 / 40 : 60 + p * 15 / 60;
String standingOf(int absences, int free) {
  final f = free < 1 ? 1 : free;
  return absences > f ? 'dropped' : absences * 5 >= f * 4 ? 'warning' : 'ok';
}
