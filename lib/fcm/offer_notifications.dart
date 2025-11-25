// lib/fcm/offer_notifications.dart

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class OfferNotificationChannel {
  static const String id = 'driver_offers';
  static const String name = 'Ride offers';
  static const String description = 'New ride offers for drivers';

  static AndroidNotificationChannel androidChannel =
  AndroidNotificationChannel(
    id,
    name,
    description: description,
    importance: Importance.max,
    playSound: true,
    enableVibration: true,
    vibrationPattern: Int64List.fromList([0, 300, 150, 300]),
    showBadge: true,
  );
}

class OfferNotifications {
  OfferNotifications._();

  static Future<void> ensureChannel(
      FlutterLocalNotificationsPlugin plugin,
      ) async {
    final android = plugin
        .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android != null) {
      await android.createNotificationChannel(
        OfferNotificationChannel.androidChannel,
      );
    }
  }

  static Future<void> showFromRemoteMessage({
    required FlutterLocalNotificationsPlugin plugin,
    required RemoteMessage message,
  }) async {
    final data = message.data;

    final notif = message.notification;
    final title =
        notif?.title ?? data['title']?.toString() ?? 'New order';
    final body =
        notif?.body ?? data['body']?.toString() ?? 'New order available';

    final payloadJson = jsonEncode(data);

    await plugin.show(
      2001,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          OfferNotificationChannel.id,
          OfferNotificationChannel.name,
          channelDescription: OfferNotificationChannel.description,
          importance: Importance.max,
          priority: Priority.high,
          playSound: true,
          enableVibration: true,
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentSound: true,
          presentBadge: true,
        ),
      ),
      payload: payloadJson,
    );
  }

  /// Навигация на экран /drive по offer_id
  static void navigateToOffer({
    required NavigatorState nav,
    required Map<String, dynamic> data,
  }) {
    final offerId = int.tryParse(data['offer_id']?.toString() ?? '');
    if (offerId == null) {
      debugPrint('[OfferNotifications] navigateToOffer: offer_id missing/invalid: ${data['offer_id']}');
      return;
    }

    nav.pushNamed('/drive',  arguments: {'force_offer_refresh': true}, );
  }
}
