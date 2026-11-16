import 'package:flutter/material.dart';

/// Keeps a tab's state (and its live subscriptions) alive when you swipe away, so it never reloads from scratch.
class KeepTabAlive extends StatefulWidget {
  final Widget child;
  const KeepTabAlive({super.key, required this.child});
  @override
  State<KeepTabAlive> createState() => _KeepAliveState();
}

class _KeepAliveState extends State<KeepTabAlive> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) { super.build(context); return widget.child; }
}
