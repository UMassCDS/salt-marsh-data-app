import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    // START: FlutterFire Configuration
    id("com.google.gms.google-services") apply false
    // END: FlutterFire Configuration
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Only applied when google-services.json is present, so builds don't fail for anyone without the file
if (file("google-services.json").exists()) {
    apply(plugin = "com.google.gms.google-services")
}

val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties()
if (keyPropertiesFile.exists()) {
    keyProperties.load(FileInputStream(keyPropertiesFile))
}

android {
    namespace = "com.saltmarshdata.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        applicationId = "com.saltmarshdata.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    flavorDimensions += "env"
    productFlavors {
        create("prod") {
            dimension = "env"
            resValue("string", "app_name", "Salt Marsh Data")
        }
        create("dev") {
            dimension = "env"
            applicationIdSuffix = ".dev"
            resValue("string", "app_name", "Salt Marsh Data DEV")
        }
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                keyAlias = keyProperties["keyAlias"].toString()
                keyPassword = keyProperties["keyPassword"].toString()
                storeFile = file(keyProperties["storeFile"].toString())
                storePassword = keyProperties["storePassword"].toString()
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keyPropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}
