# Keep flutter_local_notifications and Gson types used via reflection
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
# Keep annotations and signatures used by reflection
-keepattributes Signature, *Annotation*
# Don't warn about missing gens
-dontwarn com.google.gson.**
