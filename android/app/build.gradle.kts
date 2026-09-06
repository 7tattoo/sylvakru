import java.util.Properties
import java.io.FileInputStream
plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("org.jetbrains.kotlin.android")
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
    flavorDimensions += "app_id"
    productFlavors {
        create("kugou") {
            dimension = "app_id"
            applicationId = "com.kugou.android.auto"
        }
        create("joox") {
            dimension = "app_id"
            applicationId = "com.tencent.ibg.joox"
        }
        create("spotify") {
            dimension = "app_id"
            applicationId = "com.spotify.music"
        }
        create("apple") {
            dimension = "app_id"
            applicationId = "com.apple.android.music"
        }
        create("luna") {
            dimension = "app_id"
            applicationId = "com.luna.music.car"
        }
        create("kuwo") {
            dimension = "app_id"
            applicationId = "cn.kuwo.kwmusiccar"
        }
        create("qidian") {
            dimension = "app_id"
            applicationId = "com.qidian.QDReader"
        }
        create("weread") {
            dimension = "app_id"
            applicationId = "com.tencent.weread"
        }
        create("streammusic") {
            dimension = "app_id"
            applicationId = "cn.aqzscn.stream_music"
        }
        create("wecarflow") {
            dimension = "app_id"
            applicationId = "com.tencent.wecarflow"
        }
        create("neteaseiot") {
            dimension = "app_id"
            applicationId = "com.netease.cloudmusic.iot"
        }
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
        // applicationId 由 productFlavors 中的 applicationId 自动注入，
        // 移除单一 defaultConfig.applicationId 以避免冲突。
        // namespace 保持 com.kugou.android.auto 不变：Kotlin 包、
        // JNI 符号 Java_com_kugou_android_auto_* 都绑定在它上面。
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

kotlin {
    compilerOptions {
        jvmTarget.set(org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_11)
    }
}

flutter {
    source = "../.."
}
dependencies {
    // MainActivity.pushAtomicLyrics 使用 android.support.v4.media.MediaSessionCompat /
    // MediaMetadataCompat（原子随身听歌词协议）。audio_service 插件以 implementation
    // 方式依赖 androidx.media，不会传递到 app 编译 classpath，必须显式声明。
    implementation("androidx.media:media:1.7.0")
    implementation("com.github.HChenX:SuperLyricApi:3.4")
    testImplementation("junit:junit:4.13.2")
    // JVM 单测里没有 Android 运行时自带的 org.json
    testImplementation("org.json:json:20240303")
}
