// The JavaFX editor of AMV Flow (docs/FLOW_EDITOR_DESIGN.md 6).
//
//     gradle :amv-flow-editor:run                     an empty flow
//     gradle :amv-flow-editor:run -Pflow=<file>       open a flow file
//
// JavaFX comes from Maven Central for this computer's platform and is put
// on the class path (the launcher, amv.flow.editor.Main, is not a JavaFX
// Application, so no module path is needed).

plugins {
    application
}

val repoRoot = rootProject.extra["repoRoot"] as File
val amvFlowLibrary = rootProject.extra["amvFlowLibrary"] as String

val fxVersion = "25.0.5"
val osName: String = System.getProperty("os.name").lowercase()
val osArch: String = System.getProperty("os.arch").lowercase()
val fxPlatform = when {
    osName.contains("win") -> "win"
    osName.contains("mac") -> if (osArch == "aarch64") "mac-aarch64" else "mac"
    else -> if (osArch == "aarch64") "linux-aarch64" else "linux"
}

dependencies {
    implementation(project(":amv-flow-native"))
    listOf("base", "graphics", "controls").forEach {
        implementation("org.openjfx:javafx-$it:$fxVersion:$fxPlatform")
    }
    testImplementation(platform("org.junit:junit-bom:5.13.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

// The editor's model, without the engine or a window.
tasks.test {
    useJUnitPlatform()
}

application {
    mainClass = "amv.flow.editor.Main"
    applicationDefaultJvmArgs = listOf("--enable-native-access=ALL-UNNAMED")
}

tasks.named<JavaExec>("run") {
    systemProperty("amv.flow.library", amvFlowLibrary)
    workingDir = repoRoot
    (findProperty("flow") as String?)?.let { args(it) }
}

// A self-contained package of the editor: a Java runtime, the editor's
// jars and the engine library (with the DLLs next to it: Aravis's for the
// camera build), made by jpackage (part of the JDK).
//
//     gradle :amv-flow-editor:jpackage                     build/package/AMV Flow Editor
//     gradle :amv-flow-editor:jpackage -PpackageType=msi   an installer, where jpackage
//                                                          has the tools for one (WiX
//                                                          on Windows, dpkg or rpm on
//                                                          Linux; dmg, pkg on macOS)
val libraryFile = File(amvFlowLibrary)
val packageInput = layout.buildDirectory.dir("package-input")
val packageDir = layout.buildDirectory.dir("package")

val stagePackage = tasks.register<Sync>("stagePackage") {
    dependsOn("installDist")
    from(layout.buildDirectory.dir("install/amv-flow-editor/lib"))
    from(libraryFile.parentFile) {
        include("*.dll", "*.so", "*.so.*", "*.dylib")
    }
    into(packageInput)
}

val cleanPackage = tasks.register<Delete>("cleanPackage") {
    delete(packageDir)
}

tasks.register<Exec>("jpackage") {
    group = "distribution"
    description = "Packages the editor with a Java runtime and the engine library"
    dependsOn(stagePackage, cleanPackage)
    val type = (findProperty("packageType") as String?) ?: "app-image"
    val jpackage = File(System.getProperty("java.home"), "bin/jpackage").path
    doFirst {
        if (!libraryFile.exists()) {
            throw GradleException("no engine library at $libraryFile: run make build-flow-c first")
        }
    }
    commandLine(
        jpackage, "--type", type,
        "--name", "AMV Flow Editor",
        "--app-version", "0.2.0",
        "--input", packageInput.get().asFile.path,
        "--main-jar", "amv-flow-editor.jar",
        "--main-class", "amv.flow.editor.Main",
        "--java-options", "--enable-native-access=ALL-UNNAMED",
        // \$APPDIR: where jpackage puts the input files, the library among them.
        "--java-options", "-Damv.flow.library=\$APPDIR/${libraryFile.name}",
        "--dest", packageDir.get().asFile.path)
}
