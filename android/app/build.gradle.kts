import java.util.Properties

plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
}

android {
    namespace = "com.routecast"
    compileSdk = 34

    defaultConfig {
        applicationId = "com.routecast"
        minSdk = 26
        targetSdk = 34
        versionCode = 7
        versionName = "0.5.0"
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions {
        jvmTarget = "17"
    }

    buildFeatures {
        buildConfig = true
    }

    // Тип CIQ-подключения — билд-флаг (SPEC §4.4): hw=WIRELESS (через GCM), sim=TETHERED (adb).
    flavorDimensions += "link"
    productFlavors {
        create("hw") {
            dimension = "link"
            buildConfigField("String", "CIQ_CONNECT_TYPE", "\"WIRELESS\"")
        }
        create("sim") {
            dimension = "link"
            buildConfigField("String", "CIQ_CONNECT_TYPE", "\"TETHERED\"")
        }
    }

    // Release-подпись своим ключом (не debug). Секреты — в gitignored keystore.properties;
    // без него release остаётся неподписанным, debug/sim собираются как обычно.
    val keystorePropsFile = rootProject.file("keystore.properties")
    val hasKeystore = keystorePropsFile.exists()
    val keystoreProps = Properties()
    if (hasKeystore) { keystorePropsFile.inputStream().use { keystoreProps.load(it) } }
    signingConfigs {
        if (hasKeystore) {
            create("release") {
                storeFile = rootProject.file(keystoreProps.getProperty("storeFile"))
                storePassword = keystoreProps.getProperty("storePassword")
                keyAlias = keystoreProps.getProperty("keyAlias")
                keyPassword = keystoreProps.getProperty("keyPassword")
            }
        }
    }
    buildTypes {
        getByName("release") {
            isMinifyEnabled = false // CIQ SDK использует рефлексию — не обфусцируем
            if (hasKeystore) { signingConfig = signingConfigs.getByName("release") }
        }
    }
}

dependencies {
    implementation("com.google.code.gson:gson:2.11.0")
    implementation("com.garmin.connectiq:ciq-companion-app-sdk:2.4.0")
    testImplementation("junit:junit:4.13.2")
}

// Build-time checks only: no runtime cost on either device.
val verifyContract by tasks.registering {
    doLast {
        val repo = rootProject.projectDir.parentFile
        val watch = repo.resolve("watch/source/Cfg.mc").readText()
        val config = repo.resolve("android/app/src/main/java/com/routecast/Config.kt").readText()
        val version = android.defaultConfig.versionName!!
        check(watch.contains("const VERSION = \"v$version\"")) { "Phone/watch versions differ" }
        check(repo.resolve("CHANGELOG.md").readText().contains("## $version —")) { "Missing changelog entry" }
        val codes = Regex("Android versionCode: (\\d+)").findAll(repo.resolve("CHANGELOG.md").readText())
            .map { it.groupValues[1].toInt() }.toList()
        check(codes.firstOrNull() == android.defaultConfig.versionCode && codes.zipWithNext().all { (a, b) -> a > b }) {
            "Version codes must increase with each documented version"
        }
        check(repo.resolve("README.md").readText().contains("**$version**")) { "README version is stale" }
        check(repo.resolve("VERSIONING.md").readText().contains("**$version**")) { "VERSIONING is stale" }
        for (key in listOf("PROTOCOL_VERSION", "MAX_LINE_POINTS", "POINTS_PER_CHUNK", "MAX_MANEUVERS", "MANEUVERS_PER_CHUNK", "MAX_ROUTE_NAME")) {
            val expression = Regex("$key\\s*=\\s*(\\d+)")
            val phoneValue = expression.find(config)?.groupValues?.get(1)
            val watchValue = expression.find(watch)?.groupValues?.get(1)
            check(phoneValue != null && phoneValue == watchValue) { "Protocol constant differs: $key" }
        }
        val uuid = Regex("WATCH_APP_ID_HEX = \"([^\"]+)\"").find(config)!!.groupValues[1]
        check(repo.resolve("watch/manifest.xml").readText().contains("id=\"$uuid\"")) { "Watch application id differs" }
        val token = Regex("//[^\\r\\n]*|/\\*[\\s\\S]*?\\*/|\"(?:\\\\.|[^\"\\\\])*\"")
        val sources = repo.resolve("android/app/src/main/java").walkTopDown().filter { it.extension == "kt" } +
            repo.resolve("watch/source").walkTopDown().filter { it.extension == "mc" && !it.name.endsWith("Test.mc") }
        for (source in sources) {
            check(token.findAll(source.readText()).none { it.value.startsWith('"') && Regex("[А-Яа-яЁё]").containsMatchIn(it.value) }) {
                "User-facing source literal must be English: ${source.name}"
            }
        }
    }
}
tasks.named("preBuild") { dependsOn(verifyContract) }
