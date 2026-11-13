import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Unified Android signing key (debug *and* release, every artifact from every
// machine/CI run). The keystore itself and key.properties are gitignored; CI
// materializes them from the ANDROID_KEYSTORE_BASE64 secret via
// platforms/android/setup-signing.sh. Without signing material Gradle falls back
// to the default debug key so local builds still work (not unified).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasUnifiedKey = keystorePropertiesFile.exists()
if (hasUnifiedKey) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "dev.chatvv.chatvv"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = "27.2.12479018"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.chatvv.chatvv"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasUnifiedKey) {
            create("chatvv") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        // One key for every build type: a debug APK and a release APK share the
        // same certificate and applicationId, so they can replace each other on
        // a device and keep user data. Set by platforms/android/setup-signing.sh
        // locally and in CI.
        debug {
            signingConfig = if (hasUnifiedKey) {
                signingConfigs.getByName("chatvv")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        release {
            signingConfig = if (hasUnifiedKey) {
                signingConfigs.getByName("chatvv")
            } else {
                // Local fallback only: not unified with other machines/CI.
                signingConfigs.getByName("debug")
            }
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
