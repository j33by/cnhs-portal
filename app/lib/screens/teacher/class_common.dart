import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/calc.dart';

typedef Rows = List<Map<String, dynamic>>;
final ymd = DateFormat('yyyy-MM-dd');
String fmtNum(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Boys first then girls, alphabetical (as in the PHP class lists).
Future<Rows> loadStudents(String sectionId) => sb
    .from('students').select('id,student_no,first_name,last_name,sex')
    .eq('section_id', sectionId).eq('status', 'enrolled')
    .order('sex', ascending: false).order('last_name').order('first_name');

Future<int> currentYearId() async => (await sb.from('school_years').select('id').eq('is_current', true).single())['id'] as int;

Widget standingChip(int absences, int free) {
  final s = standingOf(absences, free);
  final col = s == 'dropped' ? Colors.red : s == 'warning' ? Colors.orange : Colors.green;
  return Chip(visualDensity: VisualDensity.compact, label: Text(s == 'ok' ? 'OK' : s == 'warning' ? 'Warning' : 'Over limit', style: const TextStyle(fontSize: 11)), backgroundColor: col.withValues(alpha: .15), side: BorderSide(color: col));
}
