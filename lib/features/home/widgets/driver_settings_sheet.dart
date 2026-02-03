import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../driver_api.dart';
import '../../../translations.dart';

class DriverSettingsSheet extends StatefulWidget {
  const DriverSettingsSheet({super.key});

  static Future<void> open(BuildContext context) {
    return showModalBottomSheet<void>(
      context: context,
      useSafeArea: true,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => const DriverSettingsSheet(),
    );
  }

  @override
  State<DriverSettingsSheet> createState() => _DriverSettingsSheetState();
}

class _DriverSettingsSheetState extends State<DriverSettingsSheet> {
  final TextEditingController _payoutCtrl = TextEditingController();
  bool _loading = true;
  bool _saving = false;
  String? _error;
  String? _accountStatus;
  String? _payoutError;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _payoutCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
      _accountStatus = null;
    });
    try {
      final res = await DriverApi.getDriverSettings(onlyConfirmed: false);
      final respStatus = (res['status'] ?? '').toString().toUpperCase();
      if (respStatus.isNotEmpty && respStatus != 'OK') {
        throw StateError(res['message']?.toString() ?? 'Error');
      }
      final data = res['data'];
      final payout =
          (data is Map ? data['payout_account'] : null) ?? res['payout_account'];
      final status = (data is Map ? data['status'] : null);
      _payoutCtrl.text = payout?.toString() ?? '';
      _accountStatus = status?.toString();
    } catch (e) {
      _error = e.toString();
    } finally {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
      _payoutError = null;
    });
    try {
      final payoutAccount = _payoutCtrl.text.trim();
      if (!RegExp(r'^\d{8,16}$').hasMatch(payoutAccount)) {
        if (mounted) {
          setState(() {
            _payoutError = t(context, 'settings.payout_account_invalid');
            _saving = false;
          });
        }
        return;
      }
      await DriverApi.setDriverSettings(
        payoutAccount: payoutAccount,
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'common.saved'))),
      );
      Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final statusText = (_accountStatus ?? '').trim();
    final statusDisplay = statusText.isEmpty ? '-' : statusText;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 8, 16, 16 + bottomInset),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            t(context, 'menu.settings'),
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          if (_loading)
            const Center(child: CircularProgressIndicator())
          else ...[
            InputDecorator(
              decoration: InputDecoration(
                labelText: t(context, 'settings.account_status'),
                border: const OutlineInputBorder(),
              ),
              child: Text(statusDisplay),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _payoutCtrl,
              decoration: InputDecoration(
                labelText: t(context, 'settings.payout_account'),
                border: const OutlineInputBorder(),
                errorText: _payoutError,
              ),
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(16),
              ],
              textInputAction: TextInputAction.done,
            ),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: const TextStyle(color: Colors.red)),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed:
                        _saving ? null : () => Navigator.of(context).pop(),
                    child: Text(t(context, 'common.cancel')),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton(
                    onPressed: _saving ? null : _save,
                    child: Text(t(context, 'common.save')),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
