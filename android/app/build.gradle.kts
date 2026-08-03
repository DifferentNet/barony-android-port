import java.util.Properties

plugins {
    id("com.android.application")
}

val baronyTargetAbi = providers.gradleProperty("baronyTargetAbi")
    .orElse("arm64-v8a")
    .get()
val baronyBuildGame = providers.gradleProperty("baronyBuildGame")
    .map(String::toBoolean)
    .orElse(false)
    .get()
val baronySignedRelease = providers.gradleProperty("baronySignedRelease")
    .map(String::toBoolean)
    .orElse(false)
    .get()
val baronyVersionCode = providers.gradleProperty("baronyVersionCode")
    .orElse("1")
    .get()
    .toInt()
val baronyVersionName = providers.gradleProperty("baronyVersionName")
    .orElse("0.0.1-bootstrap")
    .get()
val baseAndroidManifest = file("src/main/AndroidManifest.xml")
val generatedBaronyManifest = layout.buildDirectory.file("generated/baronyManifest/AndroidManifest.xml")
val baronyNoticeAssets = layout.buildDirectory.dir("generated/baronyNotices/assets")
val sdlJavaSource = rootProject.file("../external/SDL/android-project/app/src/main/java")
val generatedSdlJava = layout.buildDirectory.dir("generated/sdlJava")
require(baronyTargetAbi in setOf("arm64-v8a", "x86_64")) {
    "baronyTargetAbi must be arm64-v8a or x86_64"
}
require(!baronySignedRelease || baronyBuildGame) {
    "baronySignedRelease requires baronyBuildGame=true"
}

val releaseSigningPropertiesFile = rootProject.file("release-signing.properties")
val releaseSigningProperties = Properties()
if (releaseSigningPropertiesFile.isFile) {
    releaseSigningPropertiesFile.inputStream().use(releaseSigningProperties::load)
}
val releaseStoreFile = releaseSigningProperties.getProperty("storeFile")
val releaseKeyAlias = releaseSigningProperties.getProperty("keyAlias")
val releaseKeystorePassword = System.getenv("BARONY_RELEASE_KEYSTORE_PASSWORD")
if (baronySignedRelease) {
    require(releaseSigningPropertiesFile.isFile) {
        "Release signing metadata is missing. Run tools/create-release-keystore.ps1 first."
    }
    require(!releaseStoreFile.isNullOrBlank() && rootProject.file(releaseStoreFile).isFile) {
        "The configured release keystore does not exist."
    }
    require(!releaseKeyAlias.isNullOrBlank()) {
        "The release key alias is missing."
    }
    require(!releaseKeystorePassword.isNullOrBlank()) {
        "BARONY_RELEASE_KEYSTORE_PASSWORD is required for a signed release build."
    }
}

val generateSdlJava by tasks.registering(Sync::class) {
    from(sdlJavaSource)
    into(generatedSdlJava)

    doLast {
        val manager = generatedSdlJava.get()
            .file("org/libsdl/app/HIDDeviceManager.java")
            .asFile
        val original = manager.readText()
        val usbRegistration = "        mContext.registerReceiver(mUsbBroadcast, filter);"
        val bluetoothRegistration = "        mContext.registerReceiver(mBluetoothBroadcast, filter);"
        require(original.contains(usbRegistration) && original.contains(bluetoothRegistration)) {
            "Pinned SDL HID receiver registration changed unexpectedly"
        }

        manager.writeText(
            original
                .replace(
                    usbRegistration,
                    "        if (Build.VERSION.SDK_INT >= 33) {\n" +
                        "            mContext.registerReceiver(mUsbBroadcast, filter, Context.RECEIVER_NOT_EXPORTED);\n" +
                        "        } else {\n" +
                        "            mContext.registerReceiver(mUsbBroadcast, filter);\n" +
                        "        }"
                )
                .replace(
                    bluetoothRegistration,
                    "        if (Build.VERSION.SDK_INT >= 33) {\n" +
                        "            mContext.registerReceiver(mBluetoothBroadcast, filter, Context.RECEIVER_NOT_EXPORTED);\n" +
                        "        } else {\n" +
                        "            mContext.registerReceiver(mBluetoothBroadcast, filter);\n" +
                        "        }"
                )
        )
    }
}

val generateBaronyManifest by tasks.registering {
    inputs.file(baseAndroidManifest)
    inputs.property("baronyBuildGame", baronyBuildGame)
    outputs.file(generatedBaronyManifest)

    doLast {
        val marker = "    <!-- BARONY_GAME_PERMISSIONS -->"
        val source = baseAndroidManifest.readText()
        require(source.contains(marker)) {
            "Android manifest permission marker is missing"
        }
        val permission = if (baronyBuildGame) {
            "    <uses-permission android:name=\"android.permission.INTERNET\" />"
        }
        else {
            marker
        }
        val output = generatedBaronyManifest.get().asFile
        output.parentFile.mkdirs()
        output.writeText(source.replace(marker, permission))
    }
}

android {
    namespace = "com.zhdan.baronyport"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    ndkVersion = "28.1.13356709"

    defaultConfig {
        applicationId = "com.zhdan.baronyport"
        minSdk = 26
        targetSdk = 36
        versionCode = baronyVersionCode
        versionName = baronyVersionName
        buildConfigField("boolean", "BARONY_BUILD_GAME", baronyBuildGame.toString())

        ndk {
            abiFilters += baronyTargetAbi
        }

        externalNativeBuild {
            cmake {
                arguments += "-DANDROID_STL=c++_shared"
                arguments += "-DBARONY_ANDROID_BUILD_GAME=${if (baronyBuildGame) "ON" else "OFF"}"
                cppFlags += "-std=c++17"
            }
        }
    }

    signingConfigs {
        if (baronySignedRelease) {
            create("baronyRelease") {
                storeFile = rootProject.file(requireNotNull(releaseStoreFile))
                storePassword = requireNotNull(releaseKeystorePassword)
                keyAlias = requireNotNull(releaseKeyAlias)
                keyPassword = requireNotNull(releaseKeystorePassword)
            }
        }
    }

    buildTypes {
        getByName("debug") {
            isDebuggable = true
            isMinifyEnabled = false
        }
        getByName("release") {
            isMinifyEnabled = false
            if (baronySignedRelease) {
                signingConfig = signingConfigs.getByName("baronyRelease")
            }
        }
    }

    buildFeatures {
        buildConfig = true
    }

    packaging {
        jniLibs.excludes += "**/libz.so"
    }

    externalNativeBuild {
        cmake {
            path = file("src/main/cpp/CMakeLists.txt")
            version = "3.31.4"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    sourceSets {
        getByName("main") {
            manifest.srcFile(generatedBaronyManifest)
            java.srcDir(generatedSdlJava)
            if (baronyBuildGame) {
                assets.srcDir(baronyNoticeAssets)
            }
        }
    }
}

tasks.named("preBuild") {
    dependsOn(generateSdlJava)
    dependsOn(generateBaronyManifest)
}

if (baronyBuildGame) {
    val generateBaronyNotices by tasks.registering(Sync::class) {
        into(baronyNoticeAssets.map { it.dir("licenses") })

        val notices = mapOf(
            "../LICENSE.txt" to "Barony-and-bundled-components.txt",
            "../external/SDL/LICENSE.txt" to "SDL2.txt",
            "../external/SDL_image/LICENSE.txt" to "SDL2_image.txt",
            "../external/SDL_image/external/libpng/LICENSE" to "libpng.txt",
            "../external/SDL_image/external/zlib/LICENSE" to "zlib.txt",
            "../external/SDL_net/LICENSE.txt" to "SDL2_net.txt",
            "../external/SDL_ttf/LICENSE.txt" to "SDL2_ttf.txt",
            "../external/SDL_ttf/external/freetype/LICENSE.TXT" to "FreeType.txt",
            "../external/physfs/LICENSE.txt" to "PhysicsFS.txt",
            "../external/rapidjson/license.txt" to "RapidJSON.txt",
            "../external/openal-soft/COPYING" to "OpenAL-Soft.txt",
            "../external/ogg/COPYING" to "libogg.txt",
            "../external/vorbis/COPYING" to "libvorbis.txt",
        )
        notices.forEach { (source, outputName) ->
            from(rootProject.file(source)) {
                rename { outputName }
            }
        }
    }

    tasks.named("preBuild") {
        dependsOn(generateBaronyNotices)
    }
}
