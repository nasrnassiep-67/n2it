plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "za.co.n2it.phone"
    compileSdk = 34
    defaultConfig {
        applicationId = "za.co.n2it.softphone"
        minSdk = 26
        targetSdk = 34
        versionCode = 29
        versionName = "0.3.3"
        fun prop(n: String) = (project.findProperty(n) as String? ?: "").replace("\"", "\\\"")
        buildConfigField("String", "DEV_TENANT", "\"${prop("sipTenant")}\"")
        buildConfigField("String", "DEV_USER", "\"${prop("sipUser")}\"")
        buildConfigField("String", "DEV_PASSWORD", "\"${prop("sipPassword")}\"")
    }
    // Fixed N2IT signing key (CI secrets), so new builds install as updates.
    // Without it (local builds) the default debug key is used.
    val keystore = System.getenv("N2IT_KEYSTORE")?.let { file(it) }?.takeIf { it.exists() }
    signingConfigs {
        if (keystore != null) create("n2it") {
            storeFile = keystore
            storePassword = System.getenv("N2IT_KEYSTORE_PASSWORD")
            keyAlias = "n2it"
            keyPassword = System.getenv("N2IT_KEYSTORE_PASSWORD")
        }
    }
    buildTypes {
        // The published APK comes from assembleDebug (same file name and path for CI and the download page), so the debug
        // type must not be debuggable: adb run-as / a debugger could otherwise read the app's data (security review 2026-10-23).
        getByName("debug") {
            isDebuggable = false
            if (keystore != null) signingConfig = signingConfigs.getByName("n2it")
        }
    }
    buildFeatures { compose = true; buildConfig = true }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    packaging { jniLibs.useLegacyPackaging = true }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.09.00"))
    implementation("androidx.compose.material3:material3")
    implementation("androidx.compose.material:material-icons-extended")
    implementation("androidx.compose.ui:ui")
    implementation("androidx.activity:activity-compose:1.9.2")
    implementation("androidx.core:core-ktx:1.13.1")
    implementation("androidx.security:security-crypto:1.1.0-alpha06")
    // Calls: WebRTC (BSD) for audio, OkHttp (Apache 2.0) for the SIP WebSocket. No Linphone (AGPLv3) since 0.3.0.
    implementation("io.github.webrtc-sdk:android:144.7559.15")
    implementation("com.squareup.okhttp3:okhttp:4.12.0")
}
