plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}

android {
    namespace = "za.co.n2it.phone"
    compileSdk = 36
    defaultConfig {
        applicationId = "za.co.n2it.softphone"
        minSdk = 26
        targetSdk = 36
        versionCode = 34
        versionName = "0.3.8"
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
        // Published builds (download page APK + Play bundle) come from the release type: not debuggable, signed with the
        // N2IT key. No R8 shrinking yet: WebRTC's JNI classes need keep rules that have not been tested.
        getByName("release") {
            isMinifyEnabled = false
            signingConfig = signingConfigs.getByName(if (keystore != null) "n2it" else "debug")
        }
        // Local test builds. Not debuggable, as before (security review 2026-10-23): adb run-as could read the app's data.
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
    // Release builds run Android's "lint vital" checks; report them, but don't block a release on them
    lint { abortOnError = false; checkReleaseBuilds = false }
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
