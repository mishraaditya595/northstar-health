pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
    plugins {
        id("com.android.application") version "8.9.2"
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
