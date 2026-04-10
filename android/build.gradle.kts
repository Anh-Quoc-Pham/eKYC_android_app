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

fun hasSameDriveRoot(projectDir: File, rootDir: File): Boolean {
    val projectRoot = projectDir.toPath().root?.toString()?.lowercase()
    val rootProjectRoot = rootDir.toPath().root?.toString()?.lowercase()
    if (projectRoot == null || rootProjectRoot == null) {
        return true
    }
    return projectRoot == rootProjectRoot
}

subprojects {
    // Keep plugin caches on their original drive to avoid Windows cross-root path issues.
    if (hasSameDriveRoot(project.projectDir, rootProject.projectDir)) {
        val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
        project.layout.buildDirectory.value(newSubprojectBuildDir)
    }
}
subprojects {
    project.evaluationDependsOn(":app")
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
