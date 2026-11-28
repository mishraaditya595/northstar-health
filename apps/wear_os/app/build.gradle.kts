import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// Release signing (upload key), same as the phone app so Play App Signing gives both the same
// app signing key (a Data Layer requirement). Nothing secret is committed:
// - Locally: apps/wear_os/key.properties (gitignored) with storeFile, storePassword, keyAlias
//   and keyPassword.
// - Codemagic: the android_signing keystore reference sets CM_KEYSTORE_PATH,
//   CM_KEYSTORE_PASSWORD, CM_KEY_ALIAS and CM_KEY_PASSWORD.
// Without either, release builds fall back to the debug key, unless
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
                "apps/wear_os/key.properties must set storeFile, storePassword, keyAlias and keyPassword.",
            )
        }
        null
    }
val requireReleaseSigning = System.getenv("BEYONDREP_REQUIRE_RELEASE_SIGNING") == "true"
if (requireReleaseSigning && uploadSigning == null) {
    throw GradleException(
        "Release signing required but no upload key found: set apps/wear_os/key.properties " +
            "or the Codemagic android_signing keystore reference.",
    )
}

// The watch build has its own versionCode in the shared Play listing: the Play job passes the
// phone's build number + 1 (-Pbeyondrep.versionCode / -Pbeyondrep.versionName).
val watchVersionCode = providers.gradleProperty("beyondrep.versionCode").orNull?.toInt() ?: 1
val watchVersionName = providers.gradleProperty("beyondrep.versionName").orNull ?: "0.1.0"

android {
    namespace = "in.beyondrep.wear"
    compileSdk = 35

    defaultConfig {
        applicationId = "in.beyondrep.app"
        minSdk = 30
        targetSdk = 35
        versionCode = watchVersionCode
        versionName = watchVersionName
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

    buildFeatures {
        compose = true
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    testOptions {
        unitTests {
            // Robolectric needs the merged resources and manifest.
            isIncludeAndroidResources = true
        }
    }
}

dependencies {
    implementation(project(":core"))
    implementation(platform("androidx.compose:compose-bom:2025.04.01"))
    implementation("androidx.activity:activity-compose:1.10.1")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.wear.compose:compose-material3:1.5.0")
    implementation("androidx.wear.compose:compose-foundation:1.5.0")
    implementation("androidx.wear.compose:compose-navigation:1.5.0")
    implementation("androidx.navigation:navigation-compose:2.8.9")
    implementation("androidx.lifecycle:lifecycle-viewmodel-compose:2.8.7")
    implementation("androidx.lifecycle:lifecycle-runtime-compose:2.8.7")
    // Wear Data Layer link to the phone (stage 2). Same version as the phone app.
    implementation("com.google.android.gms:play-services-wearable:19.0.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.10.2")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.10.2")
    // Workout recording (stage 3a): a Health Services exercise session in a foreground service.
    implementation("androidx.health:health-services-client:1.0.0")
    implementation("androidx.wear:wear-ongoing:1.0.0")
    implementation("androidx.core:core-ktx:1.15.0")
    // Ambient mode for the workout screens.
    implementation("androidx.wear:wear:1.3.0")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-guava:1.10.2")

    testImplementation(kotlin("test"))
    testImplementation("junit:junit:4.13.2")
    testImplementation("org.robolectric:robolectric:4.14.1")
    testImplementation("androidx.test:core:1.6.1")
    testImplementation("org.jetbrains.kotlinx:kotlinx-coroutines-test:1.10.2")
    testImplementation(platform("androidx.compose:compose-bom:2025.04.01"))
    testImplementation("androidx.compose.ui:ui-test-junit4")
    debugImplementation("androidx.compose.ui:ui-test-manifest")
}
