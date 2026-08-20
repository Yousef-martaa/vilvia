import java.io.FileInputStream
import java.util.Properties

// Release signing (Issue #79): loaded only from android/key.properties, which
// is gitignored and never committed -- see android/key.properties.example and
// docs/RELEASE.md. Deliberately has no fallback to the debug signingConfig:
// if this file is absent, `hasReleaseSigningConfig` stays false, no release
// signingConfig is ever defined or assigned below, and the
// gradle.taskGraph.whenReady check at the bottom of this file fails any
// release build clearly and early instead.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
val hasReleaseSigningConfig = keystorePropertiesFile.exists()
if (hasReleaseSigningConfig) {
    FileInputStream(keystorePropertiesFile).use { keystoreProperties.load(it) }
}

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.vilvia.vilvia"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.vilvia.vilvia"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseSigningConfig) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            // No signingConfig is assigned at all when key.properties is
            // missing -- never falls back to the debug signingConfig. See the
            // gradle.taskGraph.whenReady check below for the resulting
            // build-time failure.
            if (hasReleaseSigningConfig) {
                signingConfig = signingConfigs.getByName("release")
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

// Fails the build clearly and early -- before any signing is attempted --
// when a release build is actually requested (assembleRelease, bundleRelease,
// etc.) without android/key.properties present. Scoped via the task graph
// (not a top-level check) so debug/profile builds are entirely unaffected
// when key.properties is absent, which is the normal state on every
// contributor's machine.
gradle.taskGraph.whenReady {
    val buildingRelease = allTasks.any { it.name.contains("Release") }
    if (buildingRelease && !hasReleaseSigningConfig) {
        throw GradleException(
            "Release build requested, but android/key.properties is missing.\n" +
                "Release builds must be signed with a real upload keystore -- " +
                "they never fall back to debug signing.\n" +
                "See docs/RELEASE.md and android/key.properties.example to set this up."
        )
    }
}
