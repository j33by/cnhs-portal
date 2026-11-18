import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

abstract class ShellEntry { const ShellEntry(); }

/// A screen reachable from the hamburger menu.
class ShellItem extends ShellEntry {
  final String id, label; final IconData icon; final Widget Function() build; final int badge; final Widget? leading;
  const ShellItem({required this.id, required this.label, required this.icon, required this.build, this.badge = 0, this.leading});
}
class ShellHeading extends ShellEntry { final String text; const ShellHeading(this.text); }
class ShellAction extends ShellEntry { final String label; final IconData icon; final VoidCallback onTap; const ShellAction(this.label, this.icon, this.onTap); }

/// Header at the top of the drawer: photo, name, ID.
class DrawerProfileHeader extends StatelessWidget {
  final String name, line1; final String? line2, photo;
  const DrawerProfileHeader({super.key, required this.name, required this.line1, this.line2, this.photo});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Container(
      width: double.infinity, color: cs.primary, padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(radius: 32, backgroundImage: photo != null ? CachedNetworkImageProvider(photo!) : null, child: photo == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 26)) : null),
        const SizedBox(height: 12),
        Text(name, style: TextStyle(color: cs.onPrimary, fontSize: 18, fontWeight: FontWeight.bold)),
        Text(line1, style: TextStyle(color: cs.onPrimary.withValues(alpha: .85))),
        if (line2 != null) Text(line2!, style: TextStyle(color: cs.onPrimary.withValues(alpha: .85), fontSize: 12)),
      ]),
    );
  }
}

/// Hamburger-menu layout. Each screen is created the first time it is opened and then kept alive,
/// so switching screens never reloads anything.
class HamburgerShell extends StatefulWidget {
  final Widget header; final List<ShellEntry> entries; final String? initialId; final List<Widget> actions;
  const HamburgerShell({super.key, required this.header, required this.entries, this.initialId, this.actions = const []});
  @override
  State<HamburgerShell> createState() => _HamburgerShellState();
}

class _HamburgerShellState extends State<HamburgerShell> {
  final scaffoldKey = GlobalKey<ScaffoldState>();
  String? selected;
  final visited = <String>{};

  @override
  void initState() { super.initState(); selected = widget.initialId; }

  List<ShellItem> get items => widget.entries.whereType<ShellItem>().toList();

  Widget _entry(ShellEntry e, ShellItem? cur) {
    if (e is ShellHeading) { return Padding(padding: const EdgeInsets.fromLTRB(24, 16, 16, 4), child: Text(e.text, style: Theme.of(context).textTheme.labelLarge)); }
    if (e is ShellAction) { return ListTile(leading: Icon(e.icon), title: Text(e.label), onTap: () { scaffoldKey.currentState?.closeDrawer(); e.onTap(); }); }
    final i = e as ShellItem;
    return ListTile(
      selected: cur?.id == i.id, selectedTileColor: Theme.of(context).colorScheme.primaryContainer.withValues(alpha: .5),
      leading: Badge(isLabelVisible: i.badge > 0, label: Text('${i.badge}'), child: i.leading ?? Icon(i.icon)),
      title: Text(i.label),
      onTap: () { setState(() => selected = i.id); scaffoldKey.currentState?.closeDrawer(); },
    );
  }

  @override
  Widget build(BuildContext c) {
    final list = items;
    final cur = list.isEmpty ? null : list.firstWhere((x) => x.id == selected, orElse: () => list.first);
    if (cur != null) { visited.add(cur.id); }
    return Scaffold(
      key: scaffoldKey,
      appBar: AppBar(title: Text(cur?.label ?? ''), actions: widget.actions),
      drawer: Drawer(child: SafeArea(top: false, child: Column(children: [
        widget.header,
        Expanded(child: ListView(padding: EdgeInsets.zero, children: [for (final e in widget.entries) _entry(e, cur)])),
      ]))),
      body: cur == null ? const SizedBox() : IndexedStack(index: list.indexOf(cur), children: [
        for (final i in list) visited.contains(i.id) ? KeyedSubtree(key: ValueKey(i.id), child: i.build()) : const SizedBox.shrink(),
      ]),
    );
  }
}
