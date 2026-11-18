import 'dart:io';
import 'package:flutter/material.dart';
import 'ui.dart';

class FamilyTab {
  final String id, label; final IconData icon, selectedIcon; final Widget Function() build; final int badge;
  const FamilyTab({required this.id, required this.label, required this.icon, required this.selectedIcon, required this.build, this.badge = 0});
}

/// Student / parent layout, the same as the teacher app: bottom bar with labels and counters on phones, rail on wide screens.
/// A tab is created the first time it is opened and then kept alive. `selected` lets any screen (e.g. Home) jump to another tab.
class FamilyShell extends StatefulWidget {
  final List<FamilyTab> tabs; final ValueNotifier<String> selected;
  final List<Widget> actions; final Widget? Function(String tabId)? top;
  const FamilyShell({super.key, required this.tabs, required this.selected, this.actions = const [], this.top});
  @override
  State<FamilyShell> createState() => _FamilyShellState();
}

class _FamilyShellState extends State<FamilyShell> {
  final visited = <String>{};
  @override
  void initState() { super.initState(); widget.selected.addListener(_changed); }
  @override
  void dispose() { widget.selected.removeListener(_changed); super.dispose(); }
  void _changed() { if (mounted) { setState(() {}); } }

  Widget _icon(FamilyTab t, bool selected) {
    final icon = Icon(selected ? t.selectedIcon : t.icon);
    return t.badge > 0 ? Badge(label: Text('${t.badge}'), child: icon) : icon;
  }

  @override
  Widget build(BuildContext c) {
    final tabs = widget.tabs;
    var i = tabs.indexWhere((t) => t.id == widget.selected.value);
    if (i < 0) { i = 0; }
    visited.add(tabs[i].id);
    final wide = Platform.isWindows || MediaQuery.sizeOf(c).width >= 900;
    final top = widget.top?.call(tabs[i].id);
    final body = Column(children: [
      const OfflineBanner(),
      if (top != null) top,
      Expanded(child: IndexedStack(index: i, children: [for (final t in tabs) visited.contains(t.id) ? TickerMode(enabled: t.id == tabs[i].id, child: KeyedSubtree(key: ValueKey(t.id), child: t.build())) : const SizedBox.shrink()])),
    ]);
    return Scaffold(
      appBar: AppBar(title: Text(tabs[i].label), actions: widget.actions),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: i, onDestinationSelected: (x) => widget.selected.value = tabs[x].id, labelType: NavigationRailLabelType.all,
                destinations: [for (final t in tabs) NavigationRailDestination(icon: _icon(t, false), selectedIcon: _icon(t, true), label: Text(t.label))],
              ),
              const VerticalDivider(width: 1), Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide ? null : NavigationBar(
        height: 68, labelBehavior: NavigationDestinationLabelBehavior.alwaysShow, selectedIndex: i,
        onDestinationSelected: (x) => widget.selected.value = tabs[x].id,
        destinations: [for (final t in tabs) NavigationDestination(icon: _icon(t, false), selectedIcon: _icon(t, true), label: t.label)],
      ),
    );
  }
}
