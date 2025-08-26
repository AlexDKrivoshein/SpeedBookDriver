plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}
android {
    namespace = "com.speedbook.taxidriver"
    compileSdk = flutter.compileSdkVersion
//    ndkVersion = flutter.ndkVersion
    ndkVersion = "29.0.13113456"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }
    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.speedbook.taxidriver"
        //minSdk = flutter.minSdkVersion
        minSdk = 23
//        targetSdk = flutter.targetSdkVersion
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        manifestPlaceholders["GOOGLE_GEO_API_KEY"] =
            project.findProperty("GOOGLE_GEO_API_KEY") as String? ?: throw GradleException("Missing GOOGLE_GEO_API_KEY")
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] =
            project.findProperty("GOOGLE_MAPS_API_KEY") as String? ?: throw GradleException("Missing GOOGLE_MAPS_API_KEY")
        manifestPlaceholders["API_URL"] =
            project.findProperty("API_URL") as String? ?: throw GradleException("Missing API_URL")
    }
    buildTypes {
        release {
            //isMinifyEnabled = true               // включает R8
            //isShrinkResources = true            // удаляет неиспользуемые ресурсы
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            //signingConfig = signingConfigs.getByName("release")
            signingConfig = signingConfigs.getByName("debug")
        }
        debug {
            // по желанию можно включить для отладки
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}
dependencies {
    // Firebase
    implementation(platform("com.google.firebase:firebase-bom:33.11.0"))
    implementation("com.google.firebase:firebase-analytics")
    // Add the dependencies for any other desired Firebase products
    // https://firebase.google.com/docs/android/setup#available-libraries
}
flutter {
    source = "../.."
}
