plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    // Firebase. This plugin requires `android/app/google-services.json` to exist at
    // build time and fails the build if it does not — see MANUAL_SETUP.md step 4.
    // That is the intended behaviour: a build that silently produced an app unable
    // to reach the project would be harder to diagnose than a build that stops.
    id("com.google.gms.google-services")
}

android {
    namespace = "com.finora.finora"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.finora.finora"
        // flutter_secure_storage needs 23+ for its EncryptedSharedPreferences
        // backing, which is what keeps the session token out of plain storage.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // Replace this with a real signing config before publishing; see
            // docs/deployment.md. The debug key is used so `flutter run
            // --release` works out of the box during development.
            signingConfig = signingConfigs.getByName("debug")

            // Shrinking is off because the release build is otherwise unsigned
            // and unverified here; turn both on alongside a real signing config.
            isMinifyEnabled = false
            isShrinkResources = false
        }
    }
}

flutter {
    source = "../.."
}
