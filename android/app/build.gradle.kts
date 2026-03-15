import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // 1. Changed namespace to match your new game identity
    namespace = "com.balaji.infinitymerge" 
    compileSdk = 36 // Standard stable version

    signingConfigs {
        create("release") {
            val keystoreProperties = Properties()
            val keystorePropertiesFile = rootProject.file("key.properties")
            
            if (keystorePropertiesFile.exists()) {
                keystorePropertiesFile.inputStream().use { input ->
                    keystoreProperties.load(input)
                }
                keyAlias = keystoreProperties.getProperty("keyAlias") ?: ""
                keyPassword = keystoreProperties.getProperty("keyPassword") ?: ""
                storePassword = keystoreProperties.getProperty("storePassword") ?: ""
                val stFile = keystoreProperties.getProperty("storeFile")
                if (!stFile.isNullOrEmpty()) {
                    storeFile = file(stFile)
                }
            } else {
                // CHANGED: Use warning instead of error so debug builds don't fail
                logger.warn("WARNING: key.properties not found. Release builds will not work.")
            }
        }
    }

    defaultConfig {
        // 2. This is the "Social Security Number" for your app. 
        // Changing this ensures it's a separate app on your phone.
        applicationId = "com.balaji.infinitymerge" 
        minSdk = 26
        targetSdk = 35 
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    buildTypes {
        getByName("debug") {
            signingConfig = signingConfigs.getByName("debug")
        }
        
        release {
            isMinifyEnabled = false
            isShrinkResources = false
            // Only use release signing if the file exists
            val keystorePropertiesFile = rootProject.file("key.properties")
            signingConfig = if (keystorePropertiesFile.exists()) {
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