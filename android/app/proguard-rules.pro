# Keep Flutter engine bootstrap and generated plugin registration.
-keep class io.flutter.embedding.** { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Keep classes/annotations used by reflection in AndroidX and Kotlin metadata.
-keepattributes *Annotation*
-keep class kotlin.Metadata { *; }

# Keep ML Kit API signatures used by native side integrations.
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**

# Preserve secure storage plugin entry points while allowing internal obfuscation.
-keep class com.it_nomads.fluttersecurestorage.** { *; }

# Retain stack trace line info only in release mapping outputs.
-renamesourcefileattribute SourceFile
-keepattributes SourceFile,LineNumberTable

# Extra hardening: strip logs from release bytecode where possible.
-assumenosideeffects class android.util.Log {
    public static int v(...);
    public static int d(...);
    public static int i(...);
}
