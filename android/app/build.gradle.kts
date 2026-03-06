plugins {
    id("com.android.application")
    // FlutterFire: plugin de Google Services (necesario para google-services.json)
    id("com.google.gms.google-services")
    id("kotlin-android")
    // El plugin de Flutter va después de Android y Kotlin
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.myl_decks"

    // SDKs/NDK requeridos por los plugins Firebase/Google
    compileSdk = 35
    ndkVersion = "27.0.12077973"

    compileOptions {
        // Puedes usar Java 17 si tu entorno ya lo tiene; 11 funciona bien con Flutter estable
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }
    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        applicationId = "com.example.myl_decks"
        minSdk = 23
        targetSdk = 35
        versionCode = 1
        versionName = "1.0"
    }

    // Desactiva shrink en debug y release para evitar el error:
    // "Removing unused resources requires unused code shrinking to be turned on"
    buildTypes {
        debug {
            isMinifyEnabled = false
            isShrinkResources = false
        }
        release {
            // Usa la firma de debug por ahora para poder correr --release sin configurar keystore
            signingConfig = signingConfigs.getByName("debug")
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
