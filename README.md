# speedbook_taxi

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Configuration

This project reads sensitive configuration such as the Google Maps API key and
backend API URL from platform-specific build settings. Provide these values when
building the app:

### Android

Create or update `android/local.properties` with the following entries:

```
GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_KEY
API_URL=https://your.backend.example
```

Gradle passes these values to the manifest placeholders used by the Dart code.

### iOS

Edit `ios/Flutter/Debug.xcconfig` and `ios/Flutter/Release.xcconfig` and set the
same variables:

```
GOOGLE_MAPS_API_KEY=YOUR_GOOGLE_KEY
API_URL=https://your.backend.example
```

Xcode injects them into `Info.plist` so that the Flutter method channel can
access them at runtime.

access them at runtime.

## Translations

`ApiService` provides a translation cache loaded from the backend. To fetch a
translation within a widget, prefer using
`ApiService.getTranslationForWidget(context, key)` which automatically uses the
runtime type of the widget as the translation namespace. The older
`getTranslation(widgetName, key)` method remains available for legacy code.