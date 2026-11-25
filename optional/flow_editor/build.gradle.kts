// Shared settings. The engine is the shared library amvflow, built by
// `make build-flow-c` into build/flow-c-lib of the repository; pass
// -PamvFlowLibrary=<path> to use another one.

val repoRoot: File = rootDir.resolve("../..").canonicalFile

val osName: String = System.getProperty("os.name").lowercase()
val libraryFile: String = when {
    osName.contains("win") -> "libamvflow.dll"
    osName.contains("mac") -> "libamvflow.dylib"
    else -> "libamvflow.so"
}

extra["repoRoot"] = repoRoot
extra["amvFlowLibrary"] = (findProperty("amvFlowLibrary") as String?)
    ?: repoRoot.resolve("build/flow-c-lib/$libraryFile").path

subprojects {
    tasks.withType<JavaCompile>().configureEach {
        options.release = 25
        options.encoding = "UTF-8"
        options.compilerArgs.addAll(listOf("-Xlint:all", "-Werror"))
    }
}
