import 'package:flutter/material.dart';
import '../brand.dart';
import '../models.dart';

class RoundFab extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  const RoundFab({super.key, required this.icon, required this.onTap, this.tooltip});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kBrandYellow,
      shape: const CircleBorder(),
      elevation: 3,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Tooltip(message: tooltip ?? '', child: Icon(icon, color: Colors.black87)),
        ),
      ),
    );
  }
}

class TrackingChip extends StatelessWidget {
  final bool active;
  final String activeText;
  final String inactiveText;

  const TrackingChip({super.key, required this.active, required this.activeText, required this.inactiveText});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPanelBg,
      borderRadius: BorderRadius.circular(24),
      elevation: 1,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(active ? Icons.my_location : Icons.location_disabled,
                color: active ? kBrandYellow : Colors.grey, size: 18),
            const SizedBox(width: 6),
            Text(active ? activeText : inactiveText, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class QuickBar extends StatelessWidget {
  final List<QuickPlace> items;
  final void Function(QuickPlace) onPick;

  const QuickBar({super.key, required this.items, required this.onPick});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 64,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(
          children: [
            for (final it in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: ActionChip(
                  onPressed: () => onPick(it),
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.access_time, size: 18),
                      const SizedBox(width: 6),
                      Text(it.title, overflow: TextOverflow.ellipsis),
                    ],
                  ),
                  backgroundColor: Colors.white,
                  shape: StadiumBorder(side: BorderSide(color: kBrandYellow, width: 2)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
