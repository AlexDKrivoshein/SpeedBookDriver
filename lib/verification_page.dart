import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

String t(BuildContext context, String key) =>
    ApiService.getTranslationForWidget(context, key);

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
  File? _selfieFile;

  int _currentStep = 0;
  bool _submitting = false;
  String? _error;

  @override
  void dispose() {
    _nameCtrl.dispose();
    super.dispose();
  }

  // ---- pick helpers ----
  Future<void> _pickImageFor(String kind) async {
    try {
      final XFile? shot = await _picker.pickImage(
        source: ImageSource.camera,
        preferredCameraDevice: kind == 'selfie'
            ? CameraDevice.front
            : CameraDevice.rear,
        imageQuality: 90,
      );
      if (shot == null) return;

      final file = File(shot.path);
      setState(() {
        if (kind == 'passport') _passportFile = file;
        if (kind == 'license') _licenseFile = file;
        if (kind == 'selfie') _selfieFile = file;
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
          !_submitting;

  // ---- API submit ----
  Future<void> _submit() async {
    if (!_canSubmit) return;
    setState(() {
      _submitting = true;
      _error = null;
    });

    try {
      String b64(File? f) =>
          f == null ? '' : base64Encode(f.readAsBytesSync());

      final payload = {
        'name': _nameCtrl.text.trim(),
        'docs': {
          'passport': b64(_passportFile),
          'driver_license': b64(_licenseFile),
          'selfie_with_passport': b64(_selfieFile),
        },
      };

      await ApiService.callAndDecode('submit_verification', payload)
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(t(context, 'verification.snackbar.sent'))),
      );
      Navigator.of(context).pop(true);
    } on TimeoutException {
      setState(() => _error = t(context, 'verification.error.timeout'));
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: Text(t(context, 'verification.title'))),
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
                    : () => setState(() => _currentStep -= 1),
                onStepContinue: () {
                  if (_currentStep == 0) {
                    if (_formKey.currentState?.validate() != true) return;
                  }
                  if (_currentStep == 1 && _passportFile == null) return;
                  if (_currentStep == 2 && _licenseFile == null) return;

                  if (_currentStep < 3) {
                    setState(() => _currentStep += 1);
                  }
                },
                controlsBuilder: (context, details) {
                  final isLast = _currentStep == 3;
                  return Row(
                    children: [
                      if (!isLast)
                        FilledButton(
                          onPressed: details.onStepContinue,
                          child: Text(t(context, 'common.next')),
                        ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: Text(t(context, 'common.back')),
                        ),
                      ],
                      if (isLast) ...[
                        FilledButton.icon(
                          onPressed: _canSubmit ? _submit : null,
                          icon: _submitting
                              ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                              : const Icon(Icons.verified_user),
                          label: Text(t(context, 'verification.submit')),
                        ),
                      ],
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
                    content: _NameStep(formKey: _formKey, nameCtrl: _nameCtrl),
                  ),
                  Step(
                    title: Text(t(context, 'verification.step.passport.title')),
                    subtitle: Text(t(context, 'verification.doc.hint.valid')),
                    isActive: _currentStep >= 1,
                    state: _passportFile != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _DocStep(
                      file: _passportFile,
                      hint: t(context, 'verification.step.passport.hint'),
                      onTake: () => _pickImageFor('passport'),
                    ),
                  ),
                  Step(
                    title: Text(t(context, 'verification.step.license.title')),
                    subtitle: Text(t(context, 'verification.doc.hint.valid')),
                    isActive: _currentStep >= 2,
                    state: _licenseFile != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _DocStep(
                      file: _licenseFile,
                      hint: t(context, 'verification.step.license.hint'),
                      onTake: () => _pickImageFor('license'),
                    ),
                  ),
                  Step(
                    title: Text(t(context, 'verification.step.selfie.title')),
                    subtitle: Text(t(context, 'verification.step.selfie.subtitle')),
                    isActive: _currentStep >= 3,
                    state: _selfieFile != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _DocStep(
                      file: _selfieFile,
                      hint: t(context, 'verification.step.selfie.hint'),
                      onTake: () => _pickImageFor('selfie'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NameStep extends StatelessWidget {
  final GlobalKey<FormState> formKey;
  final TextEditingController nameCtrl;
  const _NameStep({required this.formKey, required this.nameCtrl});

  String t(BuildContext context, String key) =>
      ApiService.getTranslationForWidget(context, key);

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
  const _DocStep({
    required this.file,
    required this.hint,
    required this.onTake,
  });

  String t(BuildContext context, String key) =>
      ApiService.getTranslationForWidget(context, key);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _RulesBox(text: hint),
        const SizedBox(height: 12),
        AspectRatio(
          aspectRatio: 4 / 3,
          child: Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surface,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: theme.dividerColor.withOpacity(0.4)),
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
        Row(
          children: [
            FilledButton.icon(
              onPressed: onTake,
              icon: const Icon(Icons.photo_camera),
              label: Text(t(context, 'verification.photo.take')),
            ),
            const SizedBox(width: 8),
            if (file != null)
              OutlinedButton.icon(
                onPressed: onTake,
                icon: const Icon(Icons.restart_alt),
                label: Text(t(context, 'verification.photo.retake')),
              ),
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
        color: theme.colorScheme.primary.withOpacity(0.06),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: theme.colorScheme.primary.withOpacity(0.25)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.info_outline, size: 18),
          const SizedBox(width: 8),
          Expanded(child: Text(text)),
        ],
      ),
    );
  }
}
