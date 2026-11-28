pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    // Versions live here (not in the root build) so a build without an Android SDK can
    // configure only :core, see `beyondrep.coreOnly` below.
    plugins {
        id("com.android.application") version "8.9.2"
        id("org.jetbrains.kotlin.android") version "2.1.20"
        id("org.jetbrains.kotlin.plugin.compose") version "2.1.20"
        id("org.jetbrains.kotlin.jvm") version "2.1.20"
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "BeyondRepWear"
include(":core")
// `-Pbeyondrep.coreOnly=true` skips the Android app so the pure-Kotlin core tests run
// on machines without an Android SDK.
if (providers.gradleProperty("beyondrep.coreOnly").orNull != "true") {
    include(":app")
}
