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
}
subprojects {
    project.evaluationDependsOn(":app")
}

// Reproducible builds: the Android NDK sits at a different absolute path on our
// release runner than on F-Droid's buildserver, and that path is baked into the
// debug info of natively-compiled plugin libraries (package:jni's
// libdartjni.so). The linker hashes the *unstripped* object into a GNU build-id
// note; stripping then discards the debug info but leaves the differing hash
// behind, so two otherwise byte-identical libraries fail F-Droid's verification
// by exactly those 20 bytes. Dropping the note removes the only path-dependent
// bytes in the APK, and applies identically to our CI and to F-Droid because it
// lives here rather than in either build environment. See docs/RELEASE.md 2a.
subprojects {
    plugins.withId("com.android.library") {
        val prefix = "-DCMAKE_SHARED_LINKER_FLAGS="
        val flag = "-Wl,--build-id=none"

        // Configured at plugin-apply time, NOT in afterEvaluate: AGP reads
        // defaultConfig during its own afterEvaluate, which is registered when
        // the plugin is applied and therefore runs before ours. Configuring
        // later is silently ignored — verified by rebuilding and finding the
        // build-id note back in place.
        extensions.configure(com.android.build.gradle.LibraryExtension::class.java) {
            defaultConfig.externalNativeBuild.cmake.arguments("$prefix$flag")
        }

        // Because we must configure first, a subproject that sets its own
        // -DCMAKE_SHARED_LINKER_FLAGS later would win — CMake takes the last -D
        // for a given variable — and would reintroduce the byte difference with
        // no build error at all. Nothing does that today; fail loudly if that
        // ever changes, rather than shipping an APK that quietly stops
        // verifying.
        //
        // Asserts the flag is PRESENT rather than merely un-clobbered, so that
        // clearing or reassigning the argument list is caught too. Scope limit:
        // this reads defaultConfig only. AGP also merges buildType and flavor
        // native args into the final CMake command line, so a conflicting value
        // set at that level would still win unseen — no dependency does that
        // today, but the check is not exhaustive.
        afterEvaluate {
            extensions.configure(com.android.build.gradle.LibraryExtension::class.java) {
                val effective = defaultConfig.externalNativeBuild.cmake.arguments
                    .lastOrNull { it.startsWith(prefix) }
                if (effective == null || !effective.contains(flag)) {
                    throw GradleException(
                        "$path would build without $flag, silently breaking " +
                            "reproducible builds. If it sets $prefix itself, merge " +
                            "the flag into that value. See docs/RELEASE.md 2a-repro.",
                    )
                }
            }
        }
    }
}

tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
