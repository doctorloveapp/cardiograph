import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val signingFile = rootProject.file("../secrets/android/key.properties")
val signingProperties = Properties()
if (signingFile.exists()) signingFile.inputStream().use { signingProperties.load(it) }

android {
    namespace = "dev.danking.cardiograph"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.2.13676358"
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }
    kotlinOptions { jvmTarget = "17" }
    defaultConfig {
        applicationId = "dev.danking.cardiograph"
        minSdk = 26
        targetSdk = 36
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }
    signingConfigs {
        create("danKing") {
            if (signingFile.exists()) {
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("danKing")
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}

dependencies {
    testImplementation("junit:junit:4.13.2")
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
    implementation("androidx.camera:camera-core:1.6.0")
    implementation("androidx.camera:camera-camera2:1.6.0")
    implementation("androidx.camera:camera-lifecycle:1.6.0")
    implementation("androidx.camera:camera-view:1.6.0")
    implementation("com.google.guava:guava:33.4.8-android")
}

flutter { source = "../.." }
