# ==============================================================================
# Flutter & Android ProGuard / R8 Rules for MyShop
# ==============================================================================

# --- Line Numbers & Attributes for Crash Reporting & De-obfuscation ---
-keepattributes SourceFile,LineNumberTable
-keepattributes *Annotation*,Signature,Exceptions,InnerClasses,EnclosingMethod

# --- Flutter Engine & Embedding ---
-dontwarn com.google.android.play.core.**
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Preserve native JNI methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Preserve classes and members annotated with @Keep or @DoNotStrip
-keep @androidx.annotation.Keep class * { *; }
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <methods>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <fields>;
}
-keepclasseswithmembers class * {
    @androidx.annotation.Keep <init>(...);
}

# --- Flutter Secure Storage (EncryptedSharedPreferences & Android KeyStore) ---
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-keep class androidx.security.crypto.** { *; }
-dontwarn androidx.security.crypto.**

# --- Connectivity Plus ---
-keep class dev.fluttercommunity.plus.connectivity.** { *; }

# --- Share Plus ---
-keep class dev.fluttercommunity.plus.share.** { *; }
-keep class androidx.core.content.FileProvider { *; }

# --- URL Launcher ---
-keep class io.flutter.plugins.urllauncher.** { *; }
-keep class androidx.browser.customtabs.** { *; }
-dontwarn androidx.browser.customtabs.**

# --- Printing & PDF ---
-keep class net.nfet.flutter.printing.** { *; }
-dontwarn android.print.**

# --- Networking / Dio / OkHttp / Okio (if referenced transitively) ---
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn javax.annotation.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**

# Keep OkHttp & Okio internals from reflection breakage
-keepnames class okhttp3.internal.publicsuffix.PublicSuffixDatabase
-dontwarn org.codehaus.mojo.animal_sniffer.*

# --- General Android & Kotlin Metadata ---
-dontwarn kotlin.reflect.**
-keepclassmembers class * extends java.lang.Enum {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
