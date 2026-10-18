import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services")
    // END: FlutterFire Configuration
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.isFile) {
    FileInputStream(keystorePropertiesFile).use(keystoreProperties::load)
}

fun signingValue(propertyName: String, environmentName: String): String? =
    System.getenv(environmentName)?.trim()?.takeIf { it.isNotEmpty() }
        ?: keystoreProperties.getProperty(propertyName)?.trim()?.takeIf { it.isNotEmpty() }

val releaseStoreFilePath = signingValue("storeFile", "MARIANOBH_KEYSTORE_PATH")
val releaseStorePassword = signingValue("storePassword", "MARIANOBH_KEYSTORE_PASSWORD")
val releaseKeyAlias = signingValue("keyAlias", "MARIANOBH_KEY_ALIAS")
val releaseKeyPassword = signingValue("keyPassword", "MARIANOBH_KEY_PASSWORD")
val releaseStoreFile = releaseStoreFilePath?.let(rootProject::file)
val releaseSigningReady = releaseStoreFile?.isFile == true &&
    listOf(releaseStorePassword, releaseKeyAlias, releaseKeyPassword).all {
        !it.isNullOrBlank()
    }
val allowDebugRelease = System.getenv("MARIANOBH_ALLOW_DEBUG_RELEASE")
    ?.equals("true", ignoreCase = true) == true
val requestedReleaseTask = gradle.startParameter.taskNames.any {
    it.contains("release", ignoreCase = true)
}

if (requestedReleaseTask && !releaseSigningReady && !allowDebugRelease) {
    throw GradleException(
        "Release signing is not configured. Add android/key.properties or the " +
            "MARIANOBH_KEYSTORE_* environment variables described in " +
            "docs/PHASE_8_RELEASE.md. For personal-phone internal testing only, " +
            "set MARIANOBH_ALLOW_DEBUG_RELEASE=true.",
    )
}

android {
    namespace = "com.marianobh.boarding_house"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // Registered Android application ID for the MarianoBH Firebase app.
        applicationId = "com.marianobh.boarding_house"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (releaseSigningReady) {
            create("release") {
                keyAlias = releaseKeyAlias
                keyPassword = releaseKeyPassword
                storeFile = releaseStoreFile
                storePassword = releaseStorePassword
            }
        }
    }

    buildTypes {
        release {
            signingConfig = when {
                releaseSigningReady -> signingConfigs.getByName("release")
                allowDebugRelease -> signingConfigs.getByName("debug")
                else -> null
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
