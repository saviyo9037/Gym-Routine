# RepTrack R8 rules. Flutter and its plugins ship their own consumer rules.

# Alarm components are referenced from the manifest (kept automatically) and the
# MethodChannel handler uses plain Kotlin classes only; keep stack traces readable.
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# org.json is used by AlarmStore (platform class, nothing to keep).
