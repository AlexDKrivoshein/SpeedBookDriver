import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

Future<void> showLocationPermissionDialog(BuildContext context) async {
  if (!context.mounted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('Доступ к геолокации'),
      content: const Text(
        'Вы навсегда запретили доступ к местоположению для этого приложения. '
        'Откройте настройки и разрешите доступ, иначе трекинг не будет работать.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const Text('Отмена'),
        ),
        TextButton(
          onPressed: () async {
            Navigator.of(ctx).pop();
            await Geolocator.openLocationSettings();
            await Geolocator.openAppSettings();
          },
          child: const Text('Открыть настройки'),
        ),
      ],
    ),
  );
}