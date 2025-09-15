import 'package:flutter/material.dart';
import '../home_page.dart';
import '../../../api_service.dart';

class VerificationBadge extends StatelessWidget {
  final DriverVerificationStatus status;
  const VerificationBadge({super.key, required this.status});

  @override
  Widget build(BuildContext context) {
    final String label;
    final Color color;

    switch (status) {
      case DriverVerificationStatus.needVerification:
        label = ApiService.getTranslationForWidget(context, 'home.verification.need');
        color = Colors.red; break;
      case DriverVerificationStatus.awaitingVerification:
        label = ApiService.getTranslationForWidget(context, 'home.verification.pending');
        color = Colors.amber; break;
      case DriverVerificationStatus.verified:
        label = ApiService.getTranslationForWidget(context, 'home.verification.verified');
        color = Colors.green; break;
      case DriverVerificationStatus.rejected:
        label = ApiService.getTranslationForWidget(context, 'home.verification.rejected');
        color = Colors.red; break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withOpacity(0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.verified_user, size: 16, color: color),
          const SizedBox(width: 6),
          Text(label, style: TextStyle(fontWeight: FontWeight.w600, color: color)),
        ],
      ),
    );
  }
}
