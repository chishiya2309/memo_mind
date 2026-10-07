import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services") apply false
}

// A checkout without cloud config must still build for offline learning.
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val teamDebugKeystore = rootProject.file("keystore/team-debug.keystore")
check(teamDebugKeystore.isFile) {
    "Missing shared development keystore: ${teamDebugKeystore.path}. " +
        "Restore android/keystore/team-debug.keystore from the repository; " +
        "do not generate a local replacement because Google Sign-In requires the registered key."
}

val releaseSigningFile = rootProject.file("key.properties")
val releaseSigningProperties = Properties().apply {
    if (releaseSigningFile.isFile) {
        releaseSigningFile.inputStream().use { load(it) }
    }
}
val releaseKeystorePath = releaseSigningProperties.getProperty("storeFile")
val releaseKeystore = releaseKeystorePath?.takeIf { it.isNotBlank() }?.let { rootProject.file(it) }

// Keep debug builds usable without private release credentials, but never fall
// back to the shared development key for a release build.
if (gradle.startParameter.taskNames.any { it.contains("release", ignoreCase = true) }) {
    check(releaseSigningFile.isFile) {
        "Release signing requires android/key.properties."
    }
    for (name in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        check(!releaseSigningProperties.getProperty(name).isNullOrBlank()) {
            "Release signing property '$name' is missing from android/key.properties."
        }
    }
    check(releaseKeystore?.isFile == true) {
        "Release keystore is missing: ${releaseKeystore?.path ?: releaseKeystorePath}."
    }
}

android {
    namespace = "vn.edu.hcmute.memo_mind"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "vn.edu.hcmute.memo_mind"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 24
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        getByName("debug") {
            storeFile = teamDebugKeystore
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
        create("release") {
            storeFile = releaseKeystore
            storePassword = releaseSigningProperties.getProperty("storePassword")
            keyAlias = releaseSigningProperties.getProperty("keyAlias")
            keyPassword = releaseSigningProperties.getProperty("keyPassword")
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
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
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    testImplementation("junit:junit:4.13.2")
}
