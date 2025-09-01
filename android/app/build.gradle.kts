// android/app/build.gradle.kts
import java.util.Properties
import java.io.FileInputStream
import org.gradle.api.GradleException

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    // Flutter plugin должен идти после Android/Kotlin
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

// читаем key.properties, если есть
val keystoreProperties = Properties().apply {
    val f = rootProject.file("key.properties")
    if (f.exists()) load(FileInputStream(f))
}

android {
    namespace = "com.speedbook.taxidriver"
    compileSdk = flutter.compileSdkVersion

    ndkVersion = "29.0.13113456"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.speedbook.taxidriver"
        minSdk = 23
        targetSdk = 35
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // требуем обязательные проектные свойства
        val geoKey = project.findProperty("GOOGLE_GEO_API_KEY") as String?
            ?: throw GradleException("Missing GOOGLE_GEO_API_KEY")
        val mapsKey = project.findProperty("GOOGLE_MAPS_API_KEY") as String?
            ?: throw GradleException("Missing GOOGLE_MAPS_API_KEY")
        val apiUrl = project.findProperty("API_URL") as String?
            ?: throw GradleException("Missing API_URL")

        // в Kotlin DSL можно так:
        manifestPlaceholders["GOOGLE_GEO_API_KEY"] = geoKey
        manifestPlaceholders["GOOGLE_MAPS_API_KEY"] = mapsKey
        manifestPlaceholders["API_URL"] = apiUrl
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = (keystoreProperties["storeFile"] as String?)?.let { file(it) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
        // debug-конфиг существует по умолчанию, трогать не нужно
    }

    buildTypes {
        getByName("release") {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
        getByName("debug") {
            // debug подписывается дефолтным debug.keystore
            isMinifyEnabled = false
        }
    }
}

dependencies {
    // Firebase BOM + нужные либы
    implementation(platform("com.google.firebase:firebase-bom:33.11.0"))
    implementation("com.google.firebase:firebase-analytics")
    // добавляй другие: auth, messaging и т.д. при необходимости
}

flutter {
    source = "../.."
}
