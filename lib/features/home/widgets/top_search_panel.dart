import 'package:flutter/material.dart';
import '../brand.dart';

class TopSearchPanel extends StatelessWidget {
  final String currentText;
  final String destinationText;
  final VoidCallback onTapCurrent;
  final VoidCallback onTapDestination;

  const TopSearchPanel({
    super.key,
    required this.currentText,
    required this.destinationText,
    required this.onTapCurrent,
    required this.onTapDestination,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: kPanelBg,
      borderRadius: BorderRadius.circular(12),
      elevation: 2,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _RowTile(
              icon: Icons.radio_button_checked,
              iconColor: kBrandYellowDark,
              text: currentText,
              onTap: onTapCurrent,
            ),
            const Divider(height: 14),
            _RowTile(
              icon: Icons.flag_outlined,
              iconColor: kBrandYellow,
              text: destinationText,
              onTap: onTapDestination,
              bold: true,
            ),
          ],
        ),
      ),
    );
  }
}

class _RowTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String text;
  final VoidCallback onTap;
  final bool bold;

  const _RowTile({
    required this.icon,
    required this.iconColor,
    required this.text,
    required this.onTap,
    this.bold = false,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Icon(icon, color: iconColor),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontWeight: bold ? FontWeight.w600 : FontWeight.w400, fontSize: 16),
              ),
            ),
            const SizedBox(width: 6),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
