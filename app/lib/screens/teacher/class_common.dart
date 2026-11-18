import 'package:flutter/material.dart';
import '../../core/teacher_data.dart';
import '../../core/offline.dart';
import 'package:intl/intl.dart';
import '../../core/api.dart';
import '../../core/calc.dart';

typedef Rows = List<Map<String, dynamic>>;
final ymd = DateFormat('yyyy-MM-dd');
String fmtNum(num v) => v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();

/// Boys first then girls, alphabetical (as in the PHP class lists).
Future<Rows> loadStudents(String sectionId) => cachedRows('stud|$sectionId', () => sb
    .from('students').select('id,student_no,first_name,last_name,sex')
    .eq('section_id', sectionId).eq('status', 'enrolled')
    .order('sex', ascending: false).order('last_name').order('first_name'));

Future<int> currentYearId() async => (await cachedRow('year-id', () => sb.from('school_years').select('id').eq('is_current', true).maybeSingle()))!['id'] as int;

/// "Math · Grade 7 Rizal" for sync messages.
String classLabelOf(String sectionId, String subjectId) {
  for (final x in TeacherData.i.classes) { if (x['section_id'] == sectionId && x['subject_id'] == subjectId) { return '${x['subject']} · Grade ${x['grade']} ${x['section']}'; } }
  return 'Class';
}

Widget standingChip(int absences, int free) {
  final s = standingOf(absences, free);
  final col = s == 'dropped' ? Colors.red : s == 'warning' ? Colors.orange : Colors.green;
  return Chip(visualDensity: VisualDensity.compact, label: Text(s == 'ok' ? 'OK' : s == 'warning' ? 'Warning' : 'Over limit', style: const TextStyle(fontSize: 11)), backgroundColor: col.withValues(alpha: .15), side: BorderSide(color: col));
}
