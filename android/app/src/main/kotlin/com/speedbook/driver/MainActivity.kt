package com.speedbook.driver

import android.content.pm.PackageManager
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.speedbook.taxidriver/config"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            CHANNEL
        ).setMethodCallHandler { call, result ->
            when (call.method) {
                "getGoogleGeoApiKey" -> {
                    try {
                        val appInfo = applicationContext.packageManager
                            .getApplicationInfo(
                                applicationContext.packageName,
                                PackageManager.GET_META_DATA
                            )
                        val apiKey = appInfo.metaData?.getString("GOOGLE_GEO_API_KEY")
                        result.success(apiKey)
                    } catch (e: Exception) {
                        result.error(
                            "META_DATA_ERROR",
                            "Error reading GOOGLE_GEO_API_KEY: ${e.message}",
                            null
                        )
                    }
                }
                "getGoogleMapsApiKey" -> {
                    try {
                        val appInfo = applicationContext.packageManager
                            .getApplicationInfo(
                                applicationContext.packageName,
                                PackageManager.GET_META_DATA
                            )
                        val apiKey = appInfo.metaData?.getString("GOOGLE_MAPS_API_KEY")
                        result.success(apiKey)
                    } catch (e: Exception) {
                        result.error(
                            "META_DATA_ERROR",
                            "Error reading GOOGLE_MAPS_API_KEY: ${e.message}",
                            null
                        )
                    }
                }
                "getApiUrl" -> {
                    try {
                        val appInfo = applicationContext.packageManager
                            .getApplicationInfo(
                                applicationContext.packageName,
                                PackageManager.GET_META_DATA
                            )
                        val apiUrl = appInfo.metaData?.getString("API_URL")
                        result.success(apiUrl)
                    } catch (e: Exception) {
                        result.error(
                            "META_DATA_ERROR",
                            "Error reading API_URL: ${e.message}",
                            null
                        )
                    }
                }
                else -> result.notImplemented()
            }
        }
    }
}