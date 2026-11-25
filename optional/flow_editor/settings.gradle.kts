// The AMV Flow editor (docs/FLOW_EDITOR_DESIGN.md 6): the Java binding of
// the engine's C API and the JavaFX editor.

dependencyResolutionManagement {
    repositories {
        mavenCentral()
    }
}

rootProject.name = "amv-flow"
include("amv-flow-native", "amv-flow-editor")
