import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';
import 'brand.dart';
import 'brand_header.dart';
import 'translations.dart';

class VerificationPage extends StatefulWidget {
  const VerificationPage({super.key});

  @override
  State<VerificationPage> createState() => _VerificationPageState();
}

class _VerificationPageState extends State<VerificationPage> {
  final _nameCtrl = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  final _picker = ImagePicker();
  File? _passportFile;
  File? _licenseFile;
  File? _commercialFile;
  File? _license2File;
  File? _selfieFile;
  File? _selfieAppFile;

  int _currentStep = 0;
  bool _submitting = false;
  int _progressTotal = 0;
  int _progressDone = 0;
  bool _selfieAppCollapsed = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ---- pick helpers ----
  Future<void> _pickImageFor(
    String kind, {
    ImageSource source = ImageSource.camera,
  }) async {
    try {
      final XFile? shot = source == ImageSource.camera
          ? await _picker.pickImage(
              source: source,
              preferredCameraDevice:
                  kind == 'selfie' ? CameraDevice.front : CameraDevice.rear,
              imageQuality: 90,
            )
          : await _picker.pickImage(
              source: source,
              imageQuality: 90,
            );
      if (shot == null) return;

      final file = File(shot.path);
      setState(() {
        if (kind == 'passport') _passportFile = file;
        if (kind == 'license') _licenseFile = file;
        if (kind == 'commercial') _commercialFile = file;
        if (kind == 'license2') _license2File = file;
        if (kind == 'selfie') _selfieFile = file;
        if (kind == 'selfie_app') _selfieAppFile = file;
      });
    } catch (e) {
      setState(() => _error = '${t(context, "verification.error.capture")}: $e');
    }
  }

  bool get _canSubmit =>
      _formKey.currentState?.validate() == true &&
          _passportFile != null &&
          _licenseFile != null &&
          _selfieFile != null &&
          _selfieAppFile != null &&
          !_submitting;

  // ---- API submit ----
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    debugPrint('[Verification] submit verification');

    try {
      String b64(File f) => base64Encode(f.readAsBytesSync());

      final payload = {
        'name': _nameCtrl.text.trim(),
      };

      final allImages = [
        {'type': 'PASSPORT_IMAGE', 'file': _passportFile},
        {'type': 'DRIVE_LICENCE_IMAGE', 'file': _licenseFile},
        {'type': 'COMMERCIAL_DRIVER_LICENSE', 'file': _commercialFile},
        {'type': 'DRIVE_LICENCE2_IMAGE', 'file': _license2File},
        {'type': 'SELFIE_IMAGE', 'file': _selfieFile},
        {'type': 'SELFIE_FOR_APP_IMAGE', 'file': _selfieAppFile},
      ];
      final images = allImages
          .where((item) => item['file'] != null)
          .cast<Map<String, Object?>>()
          .toList();

      setState(() {
        _progressTotal = images.length + 1;
        _progressDone = 0;
      });

      final reply = await ApiService
          .callAndDecode('submit_verification', payload)
          .timeout(const Duration(seconds: 300));

      final status =
          (reply is Map ? reply['status'] : null)?.toString().toUpperCase();

      if (status != 'OK') {
        debugPrint('[Verification] reply status: $status');
        final message =
            (reply is Map ? reply['message'] : null)?.toString().toUpperCase();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(t(context, 'Error: $message'))),
          );
        }
        return;
      }

      if (mounted) {
        setState(() => _progressDone += 1);
      }

      for (final item in images) {
        final file = item['file'] as File;
        final type = item['type'] as String;

        final imageReply = await ApiService
            .callAndDecode('add_verification_image', {
          'type': type,
          'base64': b64(file),
        }, timeoutSeconds: 300).timeout(const Duration(seconds: 300));

        final imageStatus = (imageReply is Map
                ? imageReply['status']
                : null)
            ?.toString()
            .toUpperCase();

        if (imageStatus != 'OK') {
          debugPrint('[Verification] add image failed: $type => $imageStatus');
          final message = (imageReply is Map
                  ? imageReply['message']
                  : null)
              ?.toString()
              .toUpperCase();
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(t(context, 'Error: $message'))),
            );
          }
          return;
        }

        if (mounted) {
          setState(() => _progressDone += 1);
        }
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'verification.snackbar.sent'))),
      );
      Navigator.of(context).popUntil((route) => route.isFirst);
    } on TimeoutException {
      debugPrint('[Verification] timeout 120s');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(t(context, 'common.timeout'))),
        );
      }
    } catch (e, st) {
      debugPrint('[Verification] error: $e\n$st');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${t(context, 'verification.snackbar.error')}: $e')),
        );
      }
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Brand.theme(Theme.of(context));
    final progressValue = _progressTotal > 0
        ? _progressDone / _progressTotal
        : null;

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
              if (_error != null)
                MaterialBanner(
                  content: Text(_error!),
                  leading: const Icon(Icons.error_outline),
                  actions: [
                    TextButton(
                      onPressed: () => setState(() => _error = null),
                      child: Text(t(context, 'common.hide')),
                    ),
                  ],
                ),
              Expanded(
                child: Stepper(
                  type: StepperType.vertical,
                  currentStep: _currentStep,
                  onStepCancel: _currentStep == 0
                      ? null
                      : () {
                          setState(() {
                            if (_currentStep == 5) {
                              _selfieAppCollapsed = false;
                            }
                            _currentStep -= 1;
                          });
                        },
                  onStepContinue: () {
                    if (_currentStep == 0) {
                      if (_formKey.currentState?.validate() != true) return;
                    }
                    if (_currentStep == 1 && _passportFile == null) return;
                    if (_currentStep == 2 && _licenseFile == null) return;
                    if (_currentStep == 5) {
                      if (_selfieAppFile == null) return;
                      if (!_selfieAppCollapsed) {
                        setState(() => _selfieAppCollapsed = true);
                      }
                      return;
                    }
                    if (_currentStep < 5) {
                      setState(() => _currentStep += 1);
                    }
                  },
                  controlsBuilder: (context, details) {
                    final isLast = _currentStep == 5 && _selfieAppCollapsed;
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (_submitting && _progressTotal > 0) ...[
                          LinearProgressIndicator(
                            value: progressValue,
                            minHeight: 6,
                            backgroundColor: theme.dividerColor.withOpacity(0.2),
                            color: Brand.textDark,
                          ),
                          const SizedBox(height: 8),
                        ],
                        Row(
                          children: [
                            if (!isLast)
                              FilledButton(
                                onPressed: details.onStepContinue,
                                child: Text(t(context, 'common.next')),
                              ),
                            if (_currentStep > 0) ...[
                              const SizedBox(width: 8),
                              OutlinedButton(
                                onPressed: details.onStepCancel,
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: Brand.textDark,
                                  side: const BorderSide(color: Brand.yellow),
                                ),
                                child: Text(t(context, 'common.back')),
                              ),
                            ],
                            if (isLast) ...[
                              const Spacer(),
                              FilledButton.icon(
                                onPressed: _canSubmit ? _submit : null,
                                icon: _submitting
                                    ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child:
                                  CircularProgressIndicator(strokeWidth: 2),
                                )
                                    : const Icon(Icons.verified_user),
                                label: Text(t(context, 'verification.submit')),
                              ),
                            ],
                          ],
                        ),
                      ],
                    );
                  },
                  steps: [
                    Step(
                      title: Text(t(context, 'verification.step.data.title')),
                      isActive: _currentStep >= 0,
                      state: _currentStep > 0
                          ? StepState.complete
                          : StepState.editing,
                      content:
                      _NameStep(formKey: _formKey, nameCtrl: _nameCtrl),
                    ),
                    Step(
                      title:
                      Text(t(context, 'verification.step.passport.title')),
                      subtitle: Text(t(context, 'verification.doc.hint.valid')),
                      isActive: _currentStep >= 1,
                      state: _passportFile != null
                          ? StepState.complete
                          : StepState.indexed,
                      content: _DocStep(
                        file: _passportFile,
                        hint: t(context, 'verification.step.passport.hint'),
                        onTake: () => _pickImageFor('passport'),
                        onPickGallery: () => _pickImageFor(
                          'passport',
                          source: ImageSource.gallery,
                        ),
                      ),
                    ),
                    Step(
                      title:
                      Text(t(context, 'verification.step.license.title')),
                      subtitle: Text(t(context, 'verification.doc.hint.valid')),
                      isActive: _currentStep >= 2,
                      state: _licenseFile != null
                          ? StepState.complete
                          : StepState.indexed,
                      content: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          _DocStep(
                            file: _licenseFile,
                            hint: t(context, 'verification.step.license.hint'),
                            onTake: () => _pickImageFor('license'),
                            onPickGallery: () => _pickImageFor(
                              'license',
                              source: ImageSource.gallery,
                            ),
                          ),
                          const SizedBox(height: 16),
                          Text(
                            t(context, 'verification.step.license2.title'),
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                          const SizedBox(height: 8),
                          _DocStep(
                            file: _license2File,
                            hint: t(context, 'verification.step.license.hint'),
                            onTake: () => _pickImageFor('license2'),
                            onPickGallery: () => _pickImageFor(
                              'license2',
                              source: ImageSource.gallery,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Step(
                      title:
                      Text(t(context, 'verification.step.commercial.title')),
                      subtitle: Text(t(context, 'verification.doc.hint.valid')),
                      isActive: _currentStep >= 3,
                      state: _commercialFile != null
                          ? StepState.complete
                          : StepState.indexed,
                      content: _DocStep(
                        file: _commercialFile,
                        hint: t(context, 'verification.step.license.hint'),
                        onTake: () => _pickImageFor('commercial'),
                        onPickGallery: () => _pickImageFor(
                          'commercial',
                          source: ImageSource.gallery,
                        ),
                      ),
                    ),
                    Step(
                      title: Text(t(context, 'verification.step.selfie.title')),
                      subtitle:
                      Text(t(context, 'verification.step.selfie.subtitle')),
                      isActive: _currentStep >= 4,
                      state: _selfieFile != null
                          ? StepState.complete
                          : StepState.indexed,
                      content: _DocStep(
                        file: _selfieFile,
                        hint: t(context, 'verification.step.selfie.hint'),
                        onTake: () => _pickImageFor('selfie'),
                        onPickGallery: () => _pickImageFor(
                          'selfie',
                          source: ImageSource.gallery,
                        ),
                      ),
                    ),
                    Step(
                      title:
                      Text(t(context, 'verification.step.selfie_app.title')),
                      subtitle:
                      Text(t(context, 'verification.step.selfie_app.subtitle')),
                      isActive: _currentStep >= 5,
                      state: _selfieAppFile != null
                          ? StepState.complete
                          : StepState.indexed,
                      content: _selfieAppCollapsed
                          ? const SizedBox.shrink()
                          : _DocStep(
                              file: _selfieAppFile,
                              hint: t(context, 'verification.step.selfie_app.hint'),
                              onTake: () => _pickImageFor('selfie_app'),
                              onPickGallery: () => _pickImageFor(
                                'selfie_app',
                                source: ImageSource.gallery,
                              ),
                              circlePreview: true,
                            ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  const _NameStep({required this.formKey, required this.nameCtrl});

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: TextFormField(
        controller: nameCtrl,
        textInputAction: TextInputAction.next,
        decoration: InputDecoration(
          labelText: t(context, 'verification.name.label'),
          hintText: t(context, 'verification.name.hint'),
          prefixIcon: const Icon(Icons.person),
        ),
        validator: (v) {
          final s = (v ?? '').trim();
          if (s.isEmpty) return t(context, 'verification.name.error.empty');
          if (s.length < 3) return t(context, 'verification.name.error.short');
          return null;
        },
      ),
    );
  }
}

class _DocStep extends StatelessWidget {
  final File? file;
  final String hint;
  final VoidCallback onTake;
  final VoidCallback? onPickGallery;
  final bool circlePreview;
  const _DocStep({
    required this.file,
    required this.hint,
    required this.onTake,
    this.onPickGallery,
    this.circlePreview = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RulesBox(text: hint),
        const SizedBox(height: 12),
        if (circlePreview)
          Center(
            child: SizedBox(
              width: 180,
              height: 180,
              child: Container(
                decoration: BoxDecoration(
                  color: theme.colorScheme.surface,
                  shape: BoxShape.circle,
                  border: Border.all(color: Brand.yellowDark),
                ),
                clipBehavior: Clip.antiAlias,
                child: file == null
                    ? Center(
                        child: Text(
                          t(context, 'verification.photo.empty'),
                          style: theme.textTheme.bodySmall,
                          textAlign: TextAlign.center,
                        ),
                      )
                    : Image.file(file!, fit: BoxFit.cover),
              ),
            ),
          )
        else
          AspectRatio(
            aspectRatio: 4 / 3,
            child: Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Brand.yellowDark),
              ),
              clipBehavior: Clip.antiAlias,
              child: file == null
                  ? Center(
                      child: Text(
                        t(context, 'verification.photo.empty'),
                        style: theme.textTheme.bodySmall,
                      ),
                    )
                  : Image.file(file!, fit: BoxFit.cover),
            ),
          ),
        const SizedBox(height: 12),
        Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: onTake,
                    icon: const Icon(Icons.photo_camera),
                    label: Text(t(context, 'verification.photo.take')),
                  ),
                ),
                if (onPickGallery != null) ...[
                  const SizedBox(width: 8),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: onPickGallery,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Brand.textDark,
                        side: const BorderSide(color: Brand.yellow),
                      ),
                      icon: const Icon(Icons.photo_library),
                      label: Text(t(context, 'verification.photo.gallery')),
                    ),
                  ),
                ],
              ],
            ),
            if (file != null) ...[
              const SizedBox(height: 8),
              OutlinedButton.icon(
                onPressed: onTake,
                icon: const Icon(Icons.restart_alt),
                label: Text(t(context, 'verification.photo.retake')),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _RulesBox extends StatelessWidget {
  final String text;
  const _RulesBox({required this.text});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Brand.yellow.withOpacity(0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Brand.yellowDark.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18, color: Brand.textDark),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
