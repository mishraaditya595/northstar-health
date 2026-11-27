// The Kotlin plugins are applied false here so they load once for all subprojects. The Android
// Gradle Plugin version lives in settings.gradle.kts (pluginManagement) so a build with
// `-Pbeyondrep.coreOnly=true` never has to resolve AGP and needs no Android SDK.
plugins {
    id("org.jetbrains.kotlin.android") version "2.1.20" apply false
    id("org.jetbrains.kotlin.plugin.compose") version "2.1.20" apply false
    id("org.jetbrains.kotlin.jvm") version "2.1.20" apply false
}
