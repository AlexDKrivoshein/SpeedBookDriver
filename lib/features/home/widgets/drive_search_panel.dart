import 'package:flutter/material.dart';
import '../brand.dart';

class DriveSearchPanel extends StatelessWidget {
  const DriveSearchPanel({
    super.key,
    required this.title,
    required this.subtitle,
    required this.elapsed,
    required this.fromText,
    required this.toText,
    required this.onCancel,
    required this.cancelLabel, // <— локализованный текст
  });

  final String title;
  final String subtitle;
  final String elapsed;
  final String fromText;
  final String toText;
  final VoidCallback onCancel;
  final String cancelLabel; // <—

  @override
  Widget build(BuildContext context) {
    return Material(
      elevation: 8,
      borderRadius: const BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.only(topLeft: Radius.circular(16), topRight: Radius.circular(16)),
        ),
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(width: 32, height: 4,
                decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(2)),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text(subtitle, style: const TextStyle(fontSize: 13, color: Colors.black54)),
                    ],
                  ),
                ),
                Text(elapsed, style: const TextStyle(fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(minHeight: 3, backgroundColor: Colors.black12, color: kBrandYellowDark),
            const SizedBox(height: 16),

            // Только ОДНА кнопка — «Отменить поездку»
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CircleAction(icon: Icons.close, label: cancelLabel, onTap: onCancel),
              ],
            ),

            const SizedBox(height: 12),
            const Divider(height: 1),
            const SizedBox(height: 8),
            //_AddressTile(icon: Icons.radio_button_checked, title: fromText, subtitle: 'Указать подъезд'),
            _AddressTile(icon: Icons.radio_button_checked, title: fromText, subtitle: ''),
            const SizedBox(height: 8),
//            _AddressTile(icon: Icons.stop, title: toText, subtitle: 'Изменить адрес поездки'),
            _AddressTile(icon: Icons.stop, title: toText, subtitle: ''),
          ],
        ),
      ),
    );
  }
}

class _CircleAction extends StatelessWidget {
  const _CircleAction({required this.icon, required this.label, required this.onTap});
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        InkWell(
          onTap: onTap,
          child: Container(
            width: 72, height: 72,
            decoration: const BoxDecoration(shape: BoxShape.circle, color: Color(0xFFF7F7F7)),
            child: Icon(icon, size: 32, color: Colors.black87),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12, color: Colors.black54)),
      ],
    );
  }
}

class _AddressTile extends StatelessWidget {
  const _AddressTile({required this.icon, required this.title, required this.subtitle});
  final IconData icon;
  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: Colors.black87),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
              const SizedBox(height: 2),
              Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.black54)),
            ],
          ),
        ),
        const Icon(Icons.chevron_right, color: Colors.black26),
      ],
    );
  }
}
