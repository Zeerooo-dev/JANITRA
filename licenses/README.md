# JANITRA third-party notices

Profile > About JANITRA > Third-party licenses reads Flutter's compiled license registry. It works offline. Flutter collects Dart/Flutter dependency licenses automatically. The root `NOTICES` adds the nine bundled font families and native Android runtime notices; Flutter includes that file in the same registry.

`android-runtime.json` records the 82 external Maven artifacts resolved from `:app:releaseRuntimeClasspath` for Build 27, with each published POM's license declaration and whether its original JAR/AAR carried a license notice. Embedded license texts were preserved verbatim. Apache-licensed artifacts without an embedded notice share the bundled Apache 2.0 text. Guava's `listenablefuture:1.0` is Apache 2.0; its parent POM supplies its license. AndroidX's repackaged Protobuf is BSD 3-Clause; `Protobuf-LICENSE.txt` is the unmodified upstream license from https://github.com/protocolbuffers/protobuf/blob/v29.3/LICENSE.

Flutter's embedding/engine notices are supplied by Flutter's own generated notices. Flutter plugin project licenses are collected from their Dart package distributions. Native build tools, JUnit and other build-only dependencies are not shipped in the APK. Font provenance and original license files are in `assets/fonts/SOURCES.md` and its linked assets.

When native dependencies change, resolve the release runtime graph again, check the original artifacts and published POMs, update `android-runtime.json` and `NOTICES`, and run the About/license tests. Do not replace upstream license or copyright text with a summary.

These are third-party notices. No new license grant for JANITRA's own source, name or logo has been selected or implied by making its repository public.
