import 'dart:async';

import 'package:flutter/material.dart';

import '../../brand.dart';
import '../../brand_header.dart';
import '../../driver_api.dart';
import '../../translations.dart';

class DrivesHistoryPage extends StatefulWidget {
  const DrivesHistoryPage({super.key});

  @override
  State<DrivesHistoryPage> createState() => _DrivesHistoryPageState();
}

class _DrivesHistoryPageState extends State<DrivesHistoryPage> {
  DateTime _fromDate = _yesterday();
  DateTime _toDate = _today();

  bool _loading = false;
  String? _error;
  List<DriverDriveHistory> _drives = const [];

  static DateTime _today() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day);
  }

  static DateTime _yesterday() => _today().subtract(const Duration(days: 1));

  @override
  void initState() {
    super.initState();
    _load();
  }

  String _fmtDate(DateTime d) {
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)}';
  }

  String _fmtDateTime(DateTime? d) {
    if (d == null) return '—';
    String two(int v) => v.toString().padLeft(2, '0');
    return '${d.year}-${two(d.month)}-${two(d.day)} '
        '${two(d.hour)}:${two(d.minute)}';
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final drives = await DriverApi.getDriversDrivesHistory(
        from: _fmtDate(_fromDate),
        to: _fmtDate(_toDate),
      );
      if (!mounted) return;
      setState(() {
        _drives = drives;
      });
    } on TimeoutException {
      if (!mounted) return;
      setState(() => _error = t(context, 'common.timeout'));
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _pickFrom() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _fromDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _fromDate = DateTime(picked.year, picked.month, picked.day);
      if (_fromDate.isAfter(_toDate)) {
        _toDate = _fromDate;
      }
    });
  }

  Future<void> _pickTo() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _toDate,
      firstDate: DateTime(2020, 1, 1),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked == null) return;
    setState(() {
      _toDate = DateTime(picked.year, picked.month, picked.day);
      if (_toDate.isBefore(_fromDate)) {
        _fromDate = _toDate;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Brand.theme(Theme.of(context));

    return Theme(
      data: theme,
      child: Scaffold(
        appBar: BrandHeader(
          showBack: true,
          onBackTap: () => Navigator.of(context).pop(),
        ),
        body: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _pickFrom,
                        icon: const Icon(Icons.date_range),
                        label: Text('From: ${_fmtDate(_fromDate)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _loading ? null : _pickTo,
                        icon: const Icon(Icons.event),
                        label: Text('To: ${_fmtDate(_toDate)}'),
                      ),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed: _loading ? null : _load,
                      child: Text(t(context, 'common.apply')),
                    ),
                  ],
                ),
              ),
              if (_loading) const LinearProgressIndicator(minHeight: 4),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      const Icon(Icons.error_outline),
                      const SizedBox(width: 8),
                      Expanded(child: Text(_error!)),
                    ],
                  ),
                ),
              Expanded(
                child: _drives.isEmpty && !_loading && _error == null
                    ? Center(child: Text(t(context, 'home.drives.empty')))
                    : SingleChildScrollView(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: Row(
                                children: [
                                  const Icon(Icons.swipe, size: 16),
                                  const SizedBox(width: 6),
                                  Text(
                                    t(context, 'home.drives.scroll_hint'),
                                    style: theme.textTheme.bodySmall,
                                  ),
                                ],
                              ),
                            ),
                            Stack(
                              children: [
                                SingleChildScrollView(
                                  scrollDirection: Axis.horizontal,
                                  child: DataTable(
                                    columns: const [
                                      DataColumn(label: Text('Date')),
                                      DataColumn(label: Text('Cost')),
                                      DataColumn(label: Text('Distance')),
                                      DataColumn(label: Text('Overprice')),
                                      DataColumn(label: Text('Ended')),
                                      DataColumn(label: Text('ID')),
                                    ],
                                    rows: [
                                      for (final d in _drives)
                                        DataRow(
                                          cells: [
                                            DataCell(Text(_fmtDateTime(d.date))),
                                            DataCell(Text(
                                                '${d.cost.toStringAsFixed(0)} ${d.currency}')),
                                            DataCell(Text('${d.distance} m')),
                                            DataCell(
                                                Text(d.overprice.toStringAsFixed(0))),
                                            DataCell(Text(_fmtDateTime(d.ended))),
                                            DataCell(Text(d.id.toString())),
                                          ],
                                        ),
                                    ],
                                  ),
                                ),
                                Positioned(
                                  right: 0,
                                  top: 0,
                                  bottom: 0,
                                  child: IgnorePointer(
                                    child: Container(
                                      width: 36,
                                      decoration: BoxDecoration(
                                        gradient: LinearGradient(
                                          begin: Alignment.centerLeft,
                                          end: Alignment.centerRight,
                                          colors: [
                                            Colors.white.withOpacity(0.0),
                                            Colors.white.withOpacity(0.9),
                                          ],
                                        ),
                                      ),
                                      child: const Align(
                                        alignment: Alignment.center,
                                        child: Icon(Icons.chevron_right),
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
