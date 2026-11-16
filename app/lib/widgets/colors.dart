import 'package:flutter/material.dart';

const _palette = [Color(0xFF1B5E3B), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFEF6C00), Color(0xFF00838F), Color(0xFFAD1457), Color(0xFF4E342E), Color(0xFF558B2F)];

/// The same subject always gets the same colour (stable across launches).
Color subjectColor(String key) {
  var h = 0;
  for (final c in key.codeUnits) { h = (h * 31 + c) & 0x7fffffff; }
  return _palette[h % _palette.length];
}

/// Advisory cards use amber everywhere so the teacher can tell them apart at a glance.
const advisoryColor = Colors.amber;
