# ==============================================================================
# Zero Production R8 / ProGuard Scrambling & Hardening Rules
# ==============================================================================

# Compress, flatten, and rename all internal package trails
# (Note: -repackageclasses 'app.zero.internal.engine' moves all obfuscated
# classes into a single flat package; -flattenpackagehierarchy is the valid
# R8/ProGuard directive if package flattening without class repackaging is used)
-repackageclasses 'app.zero.internal.engine'
-allowaccessmodification
-overloadaggressively
-renamesourcefileattribute SourceFile

# Protect required low-level assembly & JNI FFI hooks (zero_core_runtime_*)
-keepclasseswithmembers class * {
    native <methods>;
}
-keepclasseswithmembernames,includedescriptorclasses class * {
    native <methods>;
}

# Entirely erase diagnostic logs and telemetry streams from output packages
-assumenosideeffects class android.util.Log {
    public static boolean isLoggable(java.lang.String, int);
    public static int v(...);
    public static int d(...);
}

# Preserve WebRTC JavaScript Interface Methods (Call WebView Bridge)
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Preserve Kotlinx Serialization descriptors for JSON IPC with Native Core
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.AnnotationsKt

-keepclassmembers class kotlinx.serialization.json.** {
    *** Companion;
}
-keepclasseswithmembers class kotlinx.serialization.json.** {
    kotlinx.serialization.KSerializer serializer(...);
}

-keep,includedescriptorclasses class app.zero.**$$serializer { *; }
-keepclassmembers class app.zero.** {
    *** Companion;
}
-keepclasseswithmembers class app.zero.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# Enum & Parcelable runtime safety
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
-keepclassmembers class * implements android.os.Parcelable {
    public static final ** CREATOR;
}

# Suppress benign third-party warnings
-dontwarn org.boofcv.**
-dontwarn georegression.**
-dontwarn org.ddogleg.**
-dontwarn org.ejml.**
-dontwarn javax.annotation.**
-dontwarn org.codehaus.mojo.animal_sniffer.**
-dontwarn kotlinx.coroutines.debug.**
