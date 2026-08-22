import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("com.google.gms.google-services")
}

// Release signing is read from key.properties (gitignored) so the same key can
// sign every build — required for remote updates to install over the old app.
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
if (keystorePropertiesFile.exists()) {
    keystoreProperties.load(FileInputStream(keystorePropertiesFile))
}

android {
    namespace = "com.guardnest.kid"
    compileSdk = 35

    defaultConfig {
        applicationId = "com.guardnest.kid"
        minSdk = 24
        targetSdk = 35
        versionCode = 19
        versionName = "1.0.18"
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // The fleet is remote/unreachable, so we prioritise reliability over
            // size: no code shrinking/obfuscation that could crash silently.
            isMinifyEnabled = false
            isShrinkResources = false
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Falls back to debug signing if no keystore is configured yet,
                // so the project still builds. Configure key.properties before
                // shipping the real fleet build.
                signingConfigs.getByName("debug")
            }
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = "17"
    }
}

dependencies {
    implementation("androidx.core:core-ktx:1.13.1")

    // Coroutines (+ Play Services await for Firebase Task -> suspend).
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.8.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-play-services:1.8.1")

    // Firebase (BoM keeps versions aligned). Auth (anonymous) + Firestore.
    implementation(platform("com.google.firebase:firebase-bom:33.5.1"))
    implementation("com.google.firebase:firebase-auth-ktx")
    implementation("com.google.firebase:firebase-firestore-ktx")

    // On-device OCR for screenshot -> text (browser content + WhatsApp capture).
    // Unbundled variant: the ~10 MB recognition model is delivered by Google
    // Play Services and downloaded on first use, instead of being baked into the
    // APK for every ABI. Keeps the APK small (the bundled model added ~39 MB).
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")

    // Plain JVM unit tests for the pure enforcement logic (no device needed):
    // run with `gradlew :app:testDebugUnitTest`.
    testImplementation("junit:junit:4.13.2")
}
