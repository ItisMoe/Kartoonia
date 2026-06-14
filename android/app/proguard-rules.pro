# Flutter Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Prevent R8 from stripping away the Flutter native methods
-keep class io.flutter.embedding.engine.FlutterJNI {
    native <methods>;
}

# AndroidX TV Provider rules
-keep class androidx.tvprovider.** { *; }

# General Android rules
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*
-keep public class * extends android.app.Activity
-keep public class * extends android.app.Application
-keep public class * extends android.app.Service
-keep public class * extends android.content.BroadcastReceiver
-keep public class * extends android.content.ContentProvider
-keep public class * extends android.app.backup.BackupAgentHelper
-keep public class * extends android.preference.Preference

# Handle Parcelable
-keepnames class * extends android.os.Parcelable {
    public static final *** CREATOR;
}

# Video Player (ExoPlayer) rules
-keep class com.google.android.exoplayer2.** { *; }
-dontwarn com.google.android.exoplayer2.**

# WebView rules
-keep class android.webkit.** { *; }

# Fix "Missing classes" errors for Play Core (common in Flutter)
-dontwarn com.google.android.play.core.**

# Misc common warnings
-dontwarn javax.annotation.**
-dontwarn org.checkerframework.**
-dontwarn com.google.errorprone.annotations.**
