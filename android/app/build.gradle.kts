import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Optional release signing. Distribution builds must provide an (untracked)
// android/key.properties pointing at a keystore; both key.properties and *.jks
// are gitignored. Without it, the release build falls back to debug signing so
// `flutter run --release` still works for local development. See
// DEVELOPMENT.md §3.3.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(keystorePropertiesFile.inputStream())
}

android {
    namespace = "com.luminaapps.cairn"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.luminaapps.cairn"
        // Health Connect requires Android 8.0 (API 26); see DEVELOPMENT.md §3.3.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keystorePropertiesFile.exists()) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                storeFile = keystoreProperties["storeFile"]?.let { file(it) }
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    // F-Droid rejects APKs carrying AGP's dependency-metadata block: it is a
    // ~5 KB payload encrypted for Google Play, so a FOSS repo cannot inspect it
    // ("Found extra signing block 'Dependency metadata'"). AGP embeds it in the
    // APK signing block by default, which also puts it outside the zip entry
    // list — so an entry-by-entry comparison will not reveal it. Turn it off for
    // both APK and bundle outputs. See docs/RELEASE.md 2a-repro.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    buildTypes {
        release {
            // Default to debug signing so `flutter run --release` works without a
            // keystore; the line below overrides it when android/key.properties
            // exists. Each assignment is a single statement whose value has no
            // spaces, so F-Droid's signing-config scrubber strips both cleanly
            // (F-Droid builds unsigned and signs with its own key). A multi-line
            // or spaced expression here breaks that scrub. See DEVELOPMENT.md §3.3.
            signingConfig = signingConfigs.getByName("debug")
            if (keystorePropertiesFile.exists()) {
                signingConfig = signingConfigs.getByName("release")
            }
        }
    }
}

// Per-ABI version codes for F-Droid's split APKs. F-Droid ships one APK per
// ABI (smaller downloads) and needs each to carry a distinct versionCode; its
// Flutter scheme is `base * 10 + abiIndex`, matched by the `VercodeOperation`
// in the fdroiddata recipe (fdroid/com.luminaapps.cairn.yml). This is a no-op
// for the universal (fat) APK our own CI builds — that output has no ABI
// filter — so the sideload / GitHub / Forgejo releases keep the plain pubspec
// versionCode. Layout mandated by the F-Droid maintainer (Flutter ABI-split).
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abi = output.filters.find { it.filterType == "ABI" }?.identifier
        val abiVersionCode = abiCodes[abi]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride =
                variant.versionCode * 10 + abiVersionCode
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
