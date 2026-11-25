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
