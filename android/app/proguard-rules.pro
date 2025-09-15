# Branch SDK keep rules
-keep class io.branch.** { *; }
-keep class com.branch.** { *; }
-dontwarn io.branch.**
-dontwarn com.branch.**

-keep class androidx.core.content.FileProvider { *; }
