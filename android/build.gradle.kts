allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
    // Force every Android plugin module to compile against SDK 36 (some plugins,
    // e.g. flutter_plugin_android_lifecycle, now require consumers to do so).
    // Registered here, before evaluationDependsOn(":app") forces evaluation.
    afterEvaluate {
        val androidExt = project.extensions.findByName("android")
            as? com.android.build.gradle.BaseExtension
        if (androidExt != null) {
            val current = androidExt.compileSdkVersion
            if (current == null || current < "android-36") {
                androidExt.compileSdkVersion(36)
            }
        }
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
