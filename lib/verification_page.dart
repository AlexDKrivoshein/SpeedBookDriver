import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'api_service.dart';

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
        preferredCameraDevice: CameraDevice.front, // для селфи норм
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
      setState(() => _error = 'Не удалось сделать снимок: $e');
    }
  }

  String? _validateName(String? v) {
    final s = (v ?? '').trim();
    if (s.isEmpty) return 'Введите имя и фамилию как в документе';
    if (s.length < 3) return 'Слишком короткое имя';
    return null;
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
        // Можно добавить mime/type при необходимости
      };

      // Если сервер ждёт JWT-вызов:
      await ApiService.callAndDecode('submit_verification', payload)
          .timeout(const Duration(seconds: 25));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Документы отправлены на проверку')),
      );
      Navigator.of(context).pop(true); // вернёмся на Home с флагом успеха
    } on TimeoutException {
      setState(() => _error = 'Время ожидания истекло. Повторите позже.');
    } catch (e) {
      setState(() => _error = e.toString());
    } finally {
      setState(() => _submitting = false);
    }
  }

  // ---- UI ----
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Верификация')),
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
                    child: const Text('Скрыть'),
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
                          child: const Text('Далее'),
                        ),
                      if (_currentStep > 0) ...[
                        const SizedBox(width: 8),
                        TextButton(
                          onPressed: details.onStepCancel,
                          child: const Text('Назад'),
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
                          label: const Text('Отправить на проверку'),
                        ),
                      ],
                    ],
                  );
                },
                steps: [
                  Step(
                    title: const Text('Данные'),
                    isActive: _currentStep >= 0,
                    state: _currentStep > 0
                        ? StepState.complete
                        : StepState.editing,
                    content: _NameStep(formKey: _formKey, nameCtrl: _nameCtrl),
                  ),
                  Step(
                    title: const Text('Фото паспорта'),
                    subtitle: const Text('Документ должен быть настоящим и не просроченным'),
                    isActive: _currentStep >= 1,
                    state: _passportFile != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _DocStep(
                      file: _passportFile,
                      hint:
                      'Сделайте фото разворота с фото и данными. Документ должен быть действительным.',
                      onTake: () => _pickImageFor('passport'),
                    ),
                  ),
                  Step(
                    title: const Text('Фото водительских прав'),
                    subtitle: const Text('Документ должен быть настоящим и не просроченным'),
                    isActive: _currentStep >= 2,
                    state: _licenseFile != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _DocStep(
                      file: _licenseFile,
                      hint:
                      'Сделайте фото лицевой стороны прав с ФИО и сроком действия.',
                      onTake: () => _pickImageFor('license'),
                    ),
                  ),
                  Step(
                    title: const Text('Селфи с паспортом'),
                    subtitle: const Text('Лицо открыто, без головных уборов; паспорт читаем'),
                    isActive: _currentStep >= 3,
                    state: _selfieFile != null
                        ? StepState.complete
                        : StepState.indexed,
                    content: _DocStep(
                      file: _selfieFile,
                      hint:
                      'Держите паспорт открытым рядом с лицом. Лицо полностью открыто (без очков и головных уборов), паспорт читаем.',
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

  @override
  Widget build(BuildContext context) {
    return Form(
      key: formKey,
      child: TextFormField(
        controller: nameCtrl,
        textInputAction: TextInputAction.next,
        decoration: const InputDecoration(
          labelText: 'Имя и фамилия',
          hintText: 'Как в документе',
          prefixIcon: Icon(Icons.person),
        ),
        validator: (v) {
          final s = (v ?? '').trim();
          if (s.isEmpty) return 'Введите имя и фамилию как в документе';
          if (s.length < 3) return 'Слишком короткое имя';
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
                'Фото не добавлено',
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
              label: const Text('Сделать фото'),
            ),
            const SizedBox(width: 8),
            if (file != null)
              OutlinedButton.icon(
                onPressed: onTake,
                icon: const Icon(Icons.restart_alt),
                label: const Text('Переснять'),
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
