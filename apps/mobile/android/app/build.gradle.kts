import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing (upload key). Nothing secret is committed:
// - Locally: android/key.properties (gitignored) with storeFile,
//   storePassword, keyAlias and keyPassword.
// - Codemagic: the android_signing keystore reference sets CM_KEYSTORE_PATH,
//   CM_KEYSTORE_PASSWORD, CM_KEY_ALIAS and CM_KEY_PASSWORD.
// Without either, release builds fall back to the debug key so
// `flutter run --release` still works, unless
// BEYONDREP_REQUIRE_RELEASE_SIGNING=true, which the Play job sets.
val keyPropertiesFile = rootProject.file("key.properties")
val signingSource: Map<String, String?> =
    if (keyPropertiesFile.exists()) {
        val properties = Properties()
        keyPropertiesFile.inputStream().use { properties.load(it) }
        listOf("storeFile", "storePassword", "keyAlias", "keyPassword")
            .associateWith { properties.getProperty(it) }
    } else {
        mapOf(
            "storeFile" to System.getenv("CM_KEYSTORE_PATH"),
            "storePassword" to System.getenv("CM_KEYSTORE_PASSWORD"),
            "keyAlias" to System.getenv("CM_KEY_ALIAS"),
            "keyPassword" to System.getenv("CM_KEY_PASSWORD"),
        )
    }
val uploadSigning: Map<String, String>? =
    if (signingSource.values.all { !it.isNullOrBlank() }) {
        signingSource.mapValues { it.value!! }
    } else {
        if (keyPropertiesFile.exists()) {
            throw GradleException(
                "android/key.properties must set storeFile, storePassword, keyAlias and keyPassword.",
            )
        }
        null
    }
val requireReleaseSigning = System.getenv("BEYONDREP_REQUIRE_RELEASE_SIGNING") == "true"
if (requireReleaseSigning && uploadSigning == null) {
    throw GradleException(
        "Release signing required but no upload key found: set android/key.properties " +
            "or the Codemagic android_signing keystore reference.",
    )
}

android {
    namespace = "in.beyondrep.app"
    // health 14.0.0 and androidx.health.connect:connect-client 1.2.0-alpha06
    // require compiling against API 37. compileSdk does not change runtime
    // behaviour; targetSdk stays on Flutter's default.
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "in.beyondrep.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (uploadSigning != null) {
            create("upload") {
                storeFile = file(uploadSigning.getValue("storeFile"))
                storePassword = uploadSigning.getValue("storePassword")
                keyAlias = uploadSigning.getValue("keyAlias")
                keyPassword = uploadSigning.getValue("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig =
                if (uploadSigning != null) {
                    signingConfigs.getByName("upload")
                } else {
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

dependencies {
    // HeartRateWriter and WeightWriter write to Health Connect without the plugin's
    // value log. Same version as the `health` plugin 14.0.0 (its android/build.gradle);
    // keep in step.
    implementation("androidx.health.connect:connect-client:1.2.0-alpha06")
    // Wear Data Layer link to the watch app (WearLinkBridge). Must stay in step
    // with apps/wear_os so both builds speak the same Data Layer version.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
}
