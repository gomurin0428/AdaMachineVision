// The Java binding of the AMV Flow C API (optional/flow/include/amv_flow.h)
// over the Foreign Function & Memory API. No JavaFX here.

plugins {
    `java-library`
}

val repoRoot = rootProject.extra["repoRoot"] as File
val amvFlowLibrary = rootProject.extra["amvFlowLibrary"] as String

dependencies {
    testImplementation(platform("org.junit:junit-bom:5.13.4"))
    testImplementation("org.junit.jupiter:junit-jupiter")
    testRuntimeOnly("org.junit.platform:junit-platform-launcher")
}

tasks.test {
    useJUnitPlatform()
    jvmArgs("--enable-native-access=ALL-UNNAMED")
    systemProperty("amv.flow.library", amvFlowLibrary)
    // The flow file and the model image that `make test-flow` writes.
    systemProperty("amv.flow.testdir", repoRoot.resolve("build/flow-test").path)
    testLogging {
        events("passed", "failed")
        exceptionFormat = org.gradle.api.tasks.testing.logging.TestExceptionFormat.FULL
    }
}
