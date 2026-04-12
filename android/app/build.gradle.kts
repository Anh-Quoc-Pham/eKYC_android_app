import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

fun parseBooleanProperty(raw: String?, defaultValue: Boolean): Boolean {
    val normalized = raw?.trim()?.lowercase() ?: return defaultValue
    return when (normalized) {
        "1", "true", "yes", "on" -> true
        "0", "false", "no", "off" -> false
        else -> defaultValue
    }
}

val releaseKeystoreProperties = Properties()
val releaseKeystoreFile = rootProject.file("keystore.properties")
if (releaseKeystoreFile.exists()) {
    releaseKeystoreFile.inputStream().use { stream ->
        releaseKeystoreProperties.load(stream)
    }
}

val enforceReleaseSigning = parseBooleanProperty(
    providers.gradleProperty("ekyc.enforceReleaseSigning").orNull,
    false,
)
val allowDebugReleaseSigning = parseBooleanProperty(
    providers.gradleProperty("ekyc.allowDebugReleaseSigning").orNull,
    true,
)

dependencies {
    implementation("com.google.android.play:integrity:1.4.0")
}

android {
    namespace = "com.aq.ekyc.ekyc_app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    signingConfigs {
        if (releaseKeystoreFile.exists()) {
            create("release") {
                val storeFilePath = releaseKeystoreProperties.getProperty("storeFile", "").trim()
                if (storeFilePath.isNotEmpty()) {
                    storeFile = file(storeFilePath)
                }
                storePassword = releaseKeystoreProperties.getProperty("storePassword")
                keyAlias = releaseKeystoreProperties.getProperty("keyAlias")
                keyPassword = releaseKeystoreProperties.getProperty("keyPassword")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.aq.ekyc.ekyc_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            val releaseSigningConfig = signingConfigs.findByName("release")

            signingConfig = when {
                releaseSigningConfig != null -> releaseSigningConfig
                allowDebugReleaseSigning -> signingConfigs.getByName("debug")
                else -> throw GradleException(
                    "Release signing is not configured. Add android/keystore.properties or pass -Pekyc.allowDebugReleaseSigning=true for local-only release testing.",
                )
            }

            if (enforceReleaseSigning && releaseSigningConfig == null) {
                throw GradleException(
                    "Release signing is required (ekyc.enforceReleaseSigning=true) but no release signing config was found.",
                )
            }

            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro",
            )
        }
    }
}

flutter {
    source = "../.."
}
