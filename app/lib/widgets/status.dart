import 'package:flutter/material.dart';

const kDays = ['Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'];
const kDayShort = ['Sun', 'Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat'];
const kStatus = {
  'P': ['Present', Colors.green],
  'A': ['Absent', Colors.red],
  'L': ['Late', Colors.orange],
  'E': ['Excused', Colors.blueGrey],
  'N': ['No class', Color(0xFF7E57C2)],
};
Color stColor(String? s) => (kStatus[s]?[1] as Color?) ?? Colors.grey;
String stLabel(String? s) => (kStatus[s]?[0] as String?) ?? '—';
IconData stIcon(String? s) {
  switch (s) {
    case 'P': return Icons.check_circle;
    case 'A': return Icons.cancel;
    case 'L': return Icons.schedule;
    case 'E': return Icons.assignment_turned_in;
    case 'N': return Icons.event_busy;
    default: return Icons.hourglass_empty;
  }
}

String t12(String? t) { if (t == null) return '—'; final p = t.split(':'); final h = int.parse(p[0]); return '${h % 12 == 0 ? 12 : h % 12}:${p[1]} ${h >= 12 ? 'PM' : 'AM'}'; }
int minOf(String t) { final p = t.split(':'); return int.parse(p[0]) * 60 + int.parse(p[1]); }
String leftText(Duration d) {
  final m = d.inMinutes;
  if (m < 1) { return 'less than a minute'; }
  if (m < 60) { return '$m min'; }
  final h = m ~/ 60, r = m % 60;
  return r == 0 ? '$h h' : '$h h $r min';
}
