import java.util.Properties
import java.io.FileInputStream

plugins {
    id("com.android.application")

    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties()
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.kugou.android.auto"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_11
        targetCompatibility = JavaVersion.VERSION_11
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_11.toString()
    }

    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties.getProperty("keyAlias")
            keyPassword = keystoreProperties.getProperty("keyPassword")
            storeFile = keystoreProperties.getProperty("storeFile")?.let { file(it) }
            storePassword = keystoreProperties.getProperty("storePassword")
        }
    }

    defaultConfig {
        // applicationId 可由 CI 用 APP_ID 环境变量或 -PappId= 覆盖（多包名构建）。
        // namespace 必须保持 com.kugou.android.auto 不变：Kotlin 包、
        // JNI 符号 Java_com_kugou_android_auto_* 都绑定在它上面。
        applicationId = System.getenv("APP_ID")
            ?: (project.findProperty("appId") as String?)
            ?: "com.kugou.android.auto"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName

        externalNativeBuild {
            cmake {
                cppFlags += listOf("-std=c++17", "-Wall", "-Wextra")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.22.1"
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
        debug {
            applicationIdSuffix = ".debug" 
        }
        maybeCreate("profile").apply {
            initWith(getByName("debug"))
            applicationIdSuffix = ".profile"
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    configurations.all {
        resolutionStrategy {
            force("androidx.appcompat:appcompat:1.6.1")
            force("androidx.fragment:fragment:1.6.2")
        }
    }
    
}

flutter {
    source = "../.."
}

dependencies {
    implementation("com.github.HChenX:SuperLyricApi:3.4")
    testImplementation("junit:junit:4.13.2")
    // JVM 单测里没有 Android 运行时自带的 org.json
    testImplementation("org.json:json:20240303")
}
