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
        versionCode = 2
        versionName = "0.1.1"
        fun prop(n: String) = (project.findProperty(n) as String? ?: "").replace("\"", "\\\"")
        buildConfigField("String", "DEV_TENANT", "\"${prop("sipTenant")}\"")
        buildConfigField("String", "DEV_USER", "\"${prop("sipUser")}\"")
        buildConfigField("String", "DEV_PASSWORD", "\"${prop("sipPassword")}\"")
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
    implementation("org.linphone:linphone-sdk-android:5.3.95")
}
