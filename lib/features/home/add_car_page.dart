// lib/features/home/add_car_page.dart
import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../brand_header.dart';
import '../../api_service.dart';
import '../../driver_api.dart';

String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

class AddCarPage extends StatefulWidget {
  const AddCarPage({super.key});

  @override
  State<AddCarPage> createState() => _AddCarPageState();
}

class _AddCarPageState extends State<AddCarPage> {
  // ----- form / validation -----
  final _formKey = GlobalKey<FormState>();
  bool _submitting = false;
  bool _submittedOnce = false;

  // ----- loading / lookup -----
  bool _loading = true;
  String? _error;

  List<CarType> _types = const [];
  List<CarColor> _colors = const [];

  // selections
  CarType? _selType;
  CarBrand? _selBrand;
  CarModel? _selModel;
  CarColor? _selColor;
  int? _selYear;

  // years: current .. current-30 (descending)
  late final List<int> _years;

  // inputs
  final _numberCtrl = TextEditingController();

  // single required document
  final ImagePicker _picker = ImagePicker();
  Uint8List? _carDocFile;

  @override
  void initState() {
    super.initState();
    final nowYear = DateTime.now().year;
    _years = List<int>.generate(31, (i) => nowYear - i);
    _selYear = _years.first;
    _loadPreData();
  }

  @override
  void dispose() {
    _numberCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadPreData() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final pre = await DriverApi.getVerificationPreData()
          .timeout(const Duration(seconds: 15));
      setState(() {
        _types = pre.cars;
        _colors = pre.colors;
        _loading = false;
      });
    } on TimeoutException {
      setState(() {
        _error = t(context, 'common.timeout');
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ----- change handlers -----
  void _onTypeChanged(CarType? v) {
    setState(() {
      _selType = v;
      _selBrand = null;
      _selModel = null;
    });
  }

  void _onBrandChanged(CarBrand? v) {
    setState(() {
      _selBrand = v;
      _selModel = null;
    });
  }

  // ----- validators / labels -----
  String _requiredText(BuildContext ctx) => t(ctx, 'common.required'); // добавь перевод

  InputDecoration _decoration(String labelKey, {bool required = true, Widget? prefixIcon}) {
    return InputDecoration(
      label: _labelRich(labelKey, required: required),
      border: const OutlineInputBorder(),
      prefixIcon: prefixIcon,
    );
  }

  Widget _labelRich(String key, {bool required = true}) {
    final s = t(context, key);
    return RichText(
      text: TextSpan(
        text: s,
        style: Theme.of(context).textTheme.bodyMedium,
        children: required
            ? const [TextSpan(text: ' *', style: TextStyle(color: Colors.red))]
            : const [],
      ),
    );
  }

  String? _vRequiredDropdown<T>(T? v, BuildContext ctx) =>
      (v == null) ? _requiredText(ctx) : null;

  String? _vCarNumber(String? v, BuildContext ctx) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return _requiredText(ctx);
    // мягкая проверка формата
    final ok = RegExp(r'^[A-Za-z0-9 \-]{3,16}$').hasMatch(s);
    return ok ? null : _requiredText(ctx);
  }

  bool get _docValid => _carDocFile != null;

  // ----- submit -----
  Future<void> _submit() async {
    setState(() => _submittedOnce = true);

    final valid = _formKey.currentState?.validate() ?? false;
    if (!valid || !_docValid) {
      final msg = !_docValid
          ? t(context, 'home.vehicle.docs.required')
          : t(context, 'common.fill_all_required');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
      return;
    }

    setState(() => _submitting = true);
    try {
      final res = await DriverApi.submitCarVerification(
        vehicleTypeId: _selType!.id,
        brandId: _selBrand!.id,
        modelId: _selModel!.id,
        colorHex: _selColor!.hex,
        number: _numberCtrl.text.trim(),
        year: _selYear!,
        carDocFile: _carDocFile!,
      ).timeout(const Duration(seconds: 30));

      final status = (res['status'] ?? '').toString().toUpperCase();
      if (status == 'OK') {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'common.saved'))),
          );
          Navigator.of(context).pop(true);
        }
      } else {
        final errText = (res['error'] ?? res['message'] ?? 'Unknown error').toString();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(errText)));
        }
      }
    } on TimeoutException {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(t(context, 'common.timeout'))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${t(context, 'common.error')}: $e')));
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // ----- pickers -----
  Future<void> _pickFromGallery() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
        maxWidth: 2560,
      );
      if (x == null) return;
      _carDocFile = await x.readAsBytes();
      setState(() {}); // убираем ошибку у блока документов
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${t(context, "common.error")}: $e')));
      }
    }
  }

  Future<void> _takePhoto() async {
    try {
      final x = await _picker.pickImage(
        source: ImageSource.camera,
        imageQuality: 85,
        maxWidth: 2560,
      );
      if (x == null) return;
      _carDocFile = await x.readAsBytes();
      setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('${t(context, "common.error")}: $e')));
      }
    }
  }

  void _removeDoc() {
    _carDocFile = null;
    setState(() {});
  }

  // ----- UI -----
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: BrandHeader(),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _error != null
          ? Center(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton(
                onPressed: _loadPreData,
                child: Text(t(context, 'common.retry')),
              ),
            ],
          ),
        ),
      )
          : SafeArea(
        child: Form(
          key: _formKey,
          autovalidateMode: AutovalidateMode.onUserInteraction,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                t(context, 'home.car.title'),
                style: theme.textTheme.titleLarge
                    ?.copyWith(fontWeight: FontWeight.w800),
              ),
              const SizedBox(height: 16),

              // vehicle type
              DropdownButtonFormField<CarType>(
                value: _selType,
                items: _types
                    .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.name),
                ))
                    .toList(),
                onChanged: (v) => _onTypeChanged(v),
                validator: (v) => _vRequiredDropdown(v, context),
                decoration: _decoration('home.vehicle.type', required: true),
              ),
              const SizedBox(height: 12),

              // brand
              DropdownButtonFormField<CarBrand>(
                value: _selBrand,
                items: (_selType?.brands ?? const [])
                    .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.name),
                ))
                    .toList(),
                onChanged: (_selType == null) ? null : (v) => _onBrandChanged(v),
                validator: (v) => _vRequiredDropdown(v, context),
                decoration: _decoration('home.vehicle.brand', required: true),
              ),
              const SizedBox(height: 12),

              // model
              DropdownButtonFormField<CarModel>(
                value: _selModel,
                items: (_selBrand?.models ?? const [])
                    .map((e) => DropdownMenuItem(
                  value: e,
                  child: Text(e.name),
                ))
                    .toList(),
                onChanged: (_selBrand == null) ? null : (v) => setState(() => _selModel = v),
                validator: (v) => _vRequiredDropdown(v, context),
                decoration: _decoration('home.vehicle.model', required: true),
              ),
              const SizedBox(height: 12),

              // color
              DropdownButtonFormField<CarColor>(
                value: _selColor,
                items: _colors
                    .map((c) => DropdownMenuItem(
                  value: c,
                  child: Row(
                    children: [
                      Container(
                        width: 16,
                        height: 16,
                        margin: const EdgeInsets.only(right: 8),
                        decoration: BoxDecoration(
                          color: _parseHex(c.hex),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.black12),
                        ),
                      ),
                      Text(c.name),
                    ],
                  ),
                ))
                    .toList(),
                onChanged: (v) => setState(() => _selColor = v),
                validator: (v) => _vRequiredDropdown(v, context),
                decoration: _decoration('home.vehicle.color', required: true),
              ),
              const SizedBox(height: 12),

              // number
              TextFormField(
                controller: _numberCtrl,
                textCapitalization: TextCapitalization.characters,
                maxLength: 16,
                validator: (v) => _vCarNumber(v, context),
                decoration: _decoration('home.vehicle.number', required: true,
                    prefixIcon: const Icon(Icons.numbers)),
              ),
              const SizedBox(height: 12),

              // year
              DropdownButtonFormField<int>(
                value: _selYear,
                items: _years
                    .map((y) => DropdownMenuItem(
                  value: y,
                  child: Text(y.toString()),
                ))
                    .toList(),
                onChanged: (v) => setState(() => _selYear = v),
                validator: (v) => _vRequiredDropdown(v, context),
                decoration: _decoration('home.vehicle.year', required: true),
              ),
              const SizedBox(height: 12),

              // vehicle document (required)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _labelRich('home.vehicle.docs', required: true),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _pickFromGallery,
                          icon: const Icon(Icons.photo_library_outlined),
                          label: Text(t(context, 'home.vehicle.docs.add')),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _takePhoto,
                          icon: const Icon(Icons.photo_camera_outlined),
                          label: Text(t(context, 'home.vehicle.docs.take')),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  if (_carDocFile != null)
                    Stack(
                      alignment: Alignment.topRight,
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.memory(
                            _carDocFile!,
                            width: 120,
                            height: 120,
                            fit: BoxFit.cover,
                          ),
                        ),
                        Material(
                          color: Colors.transparent,
                          child: IconButton(
                            onPressed: _removeDoc,
                            icon: const Icon(Icons.close),
                            tooltip: t(context, 'common.remove'),
                            style: ButtonStyle(
                              backgroundColor: WidgetStateProperty.all(Colors.black45),
                              foregroundColor: WidgetStateProperty.all(Colors.white),
                            ),
                          ),
                        ),
                      ],
                    )
                  else if (_submittedOnce)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        t(context, 'home.vehicle.docs.required'),
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                          fontSize: 12,
                        ),
                      ),
                    )
                  else
                    Text(
                      t(context, 'home.vehicle.docs.required'),
                      style: theme.textTheme.bodySmall?.copyWith(color: theme.hintColor),
                    ),
                ],
              ),
              const SizedBox(height: 20),

              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _submitting ? null : _submit,
                  icon: _submitting
                      ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                      : const Icon(Icons.save),
                  label: Text(t(context, 'common.save')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Color _parseHex(String hex) {
    final s = hex.replaceAll('#', '');
    final v = int.tryParse(s, radix: 16) ?? 0x000000;
    return Color(0xFF000000 | v);
  }
}

class _Labeled extends StatelessWidget {
  final String label;
  final Widget child;
  const _Labeled({required this.label, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
        const SizedBox(height: 6),
        child,
      ],
    );
  }
}
