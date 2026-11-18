import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../core/messenger.dart';
import '../core/offline.dart';
import 'package:intl/intl.dart';

/// School photo banner with a soft dark overlay so white text stays readable. Used behind the Home and Profile headers.
class SchoolBackdrop extends StatelessWidget {
  final Widget child;
  const SchoolBackdrop({super.key, required this.child});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return ClipRRect(
      borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
      child: Stack(children: [
        Positioned.fill(child: Image.asset('assets/images/hero_school.jpg', fit: BoxFit.cover, alignment: Alignment.center,
            errorBuilder: (_, __, ___) => DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(colors: [cs.primary, Color.lerp(cs.primary, Colors.black, .35)!]))))),
        Positioned.fill(child: DecoratedBox(decoration: BoxDecoration(gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.black.withValues(alpha: .35), Colors.black.withValues(alpha: .62)])))),
        SizedBox(width: double.infinity, child: Padding(padding: const EdgeInsets.fromLTRB(16, 20, 16, 26), child: child)),
      ]),
    );
  }
}

/// Header with the photo, name and ID on top of the school banner (same look as the teacher Home).
class HeroHeader extends StatelessWidget {
  final String greeting, name; final String? photo, idLabel, idValue, subtitle; final Widget? child;
  const HeroHeader({super.key, required this.greeting, required this.name, this.photo, this.idLabel, this.idValue, this.subtitle, this.child});
  @override
  Widget build(BuildContext c) {
    const fg = Colors.white;
    return SchoolBackdrop(
      child: Column(children: [
        Text(greeting, style: TextStyle(color: fg.withValues(alpha: .9))),
        const SizedBox(height: 12),
        Container(
          padding: const EdgeInsets.all(3), decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
          child: CircleAvatar(radius: 52, backgroundImage: photo != null ? CachedNetworkImageProvider(photo!) : null,
              child: photo == null ? Text(name.isEmpty ? '?' : name[0].toUpperCase(), style: const TextStyle(fontSize: 38)) : null),
        ),
        const SizedBox(height: 12),
        Text(name, textAlign: TextAlign.center, style: const TextStyle(color: fg, fontSize: 22, fontWeight: FontWeight.bold)),
        if (subtitle != null) Padding(padding: const EdgeInsets.only(top: 4), child: Text(subtitle!, textAlign: TextAlign.center, style: TextStyle(color: fg.withValues(alpha: .92)))),
        if (idValue != null) ...[
          const SizedBox(height: 10),
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () { Clipboard.setData(ClipboardData(text: idValue!)); toast('${idLabel ?? 'ID'} copied'); },
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(color: Colors.white.withValues(alpha: .2), borderRadius: BorderRadius.circular(20)),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                const Icon(Icons.badge, size: 16, color: fg), const SizedBox(width: 6),
                Text('${idLabel ?? 'ID'}  $idValue', style: const TextStyle(color: fg, fontWeight: FontWeight.w600, letterSpacing: .5)),
                const SizedBox(width: 6), Icon(Icons.copy, size: 14, color: fg.withValues(alpha: .8)),
              ]),
            ),
          ),
        ],
        if (child != null) ...[const SizedBox(height: 12), child!],
      ]),
    );
  }
}

class SectionTitle extends StatelessWidget {
  final String text; final IconData? icon; final Widget? trailing;
  const SectionTitle(this.text, {super.key, this.icon, this.trailing});
  @override
  Widget build(BuildContext c) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          if (icon != null) Padding(padding: const EdgeInsets.only(right: 8), child: Icon(icon, size: 20, color: Theme.of(c).colorScheme.primary)),
          Expanded(child: Text(text, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold))),
          if (trailing != null) trailing!,
        ]),
      );
}

class Pill extends StatelessWidget {
  final String text; final Color color; final IconData? icon; final bool solid;
  const Pill(this.text, this.color, {super.key, this.icon, this.solid = false});
  @override
  Widget build(BuildContext c) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
        decoration: BoxDecoration(color: solid ? color : color.withValues(alpha: .14), borderRadius: BorderRadius.circular(20)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) Padding(padding: const EdgeInsets.only(right: 4), child: Icon(icon, size: 13, color: solid ? Colors.white : color)),
          Text(text, style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: solid ? Colors.white : color)),
        ]),
      );
}

/// Soft rounded card used everywhere in the family screens.
class SoftCard extends StatelessWidget {
  final Widget child; final EdgeInsets padding; final Color? color, border; final VoidCallback? onTap;
  const SoftCard({super.key, required this.child, this.padding = const EdgeInsets.all(14), this.color, this.border, this.onTap});
  @override
  Widget build(BuildContext c) {
    final cs = Theme.of(c).colorScheme;
    return Card(
      elevation: 0, margin: EdgeInsets.zero, clipBehavior: Clip.antiAlias, color: color ?? cs.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18), side: BorderSide(color: border ?? Theme.of(c).dividerColor.withValues(alpha: .35))),
      child: onTap == null ? Padding(padding: padding, child: child) : InkWell(onTap: onTap, child: Padding(padding: padding, child: child)),
    );
  }
}

class EmptyState extends StatelessWidget {
  final IconData icon; final String title, message; final Widget? action;
  const EmptyState({super.key, required this.icon, required this.title, this.message = '', this.action});
  @override
  Widget build(BuildContext c) => Center(child: Padding(padding: const EdgeInsets.all(28), child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(padding: const EdgeInsets.all(18), decoration: BoxDecoration(color: Theme.of(c).colorScheme.primaryContainer.withValues(alpha: .5), shape: BoxShape.circle), child: Icon(icon, size: 40, color: Theme.of(c).colorScheme.primary)),
        const SizedBox(height: 14),
        Text(title, textAlign: TextAlign.center, style: Theme.of(c).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        if (message.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 6), child: Text(message, textAlign: TextAlign.center, style: TextStyle(color: Theme.of(c).hintColor))),
        if (action != null) Padding(padding: const EdgeInsets.only(top: 14), child: action!),
      ])));
}

/// Thin strip under the app bar: amber while there is no internet (with the time of the last update), green for a moment when it is back.
class OfflineBanner extends StatelessWidget {
  const OfflineBanner({super.key});
  @override
  Widget build(BuildContext c) => ListenableBuilder(listenable: Net.i, builder: (c, _) {
        if (!Net.i.online) {
          final t = Net.i.lastOnline;
          return Container(
            width: double.infinity, color: Colors.amber.shade800, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: Row(children: [
              const Icon(Icons.cloud_off, size: 17, color: Colors.white), const SizedBox(width: 8),
              Expanded(child: Text(t == null ? "You're offline. Showing your last saved data." : "You're offline. Showing data saved ${DateFormat('MMM d, h:mm a').format(t)}.", style: const TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600))),
            ]),
          );
        }
        if (Net.i.justBack) {
          return Container(
            width: double.infinity, color: Colors.green.shade700, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
            child: const Row(children: [Icon(Icons.cloud_done, size: 17, color: Colors.white), SizedBox(width: 8), Expanded(child: Text("Back online. Updating live data…", style: TextStyle(color: Colors.white, fontSize: 12.5, fontWeight: FontWeight.w600)))]),
          );
        }
        return const SizedBox.shrink();
      });
}
