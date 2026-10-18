# Flutter Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
# App Rules
-keep class com.classora.classora_mobile.** { *; }

# LiveKit & WebRTC Keep Rules
-keep class io.livekit.plugin.** { *; }
-keep class io.livekit.android.** { *; }
-keep class livekit.org.webrtc.** { *; }
-keep class org.webrtc.** { *; }
-keep class com.cloudwebrtc.webrtc.** { *; }

# Prevent native JNI methods from being renamed/stripped
-keepclasseswithmembernames class * {
    native <methods>;
}

# Keep serializable model classes & JSON reflection
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    !static !transient <fields>;
    !private <fields>;
    !private <methods>;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}

# Razorpay SDK rules
-keep class com.razorpay.** {*;}
-dontwarn com.razorpay.**

# Firebase & Google Play Services
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-dontwarn com.google.android.play.core.**

# Android Architecture Components
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable

