# R8 / ProGuard keep rules for release builds.
#
# Flutter enables minification + resource shrinking for release builds and
# automatically includes this file (see the Flutter Gradle plugin). Rules here
# protect classes that dependencies instantiate by reflection, which R8 "full
# mode" (the AGP default) would otherwise strip — producing crashes that appear
# ONLY in release builds, never in debug.

# --- WorkManager / Room (opportunistic background sync, DESIGN.md §4.4) ---
# WorkManager stores its state in a Room database. Room loads the generated
# `<Name>_Impl` subclass reflectively (Class.forName on the base class name +
# "_Impl") and invokes its no-arg constructor. R8 full mode removes that
# constructor, so the app crashes on launch with:
#   java.lang.NoSuchMethodException: androidx.work.impl.WorkDatabase_Impl.<init> []
# Keep every Room database subclass name and its no-arg constructor.
-keep class * extends androidx.room.RoomDatabase {
    <init>();
}
