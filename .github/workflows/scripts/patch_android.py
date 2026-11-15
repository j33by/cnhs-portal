"""Patch the freshly generated android/ folder (flutter create) for CNHS Portal:
 - applicationId/namespace -> io.cnhs.portal (must match google-services.json)
 - INTERNET + POST_NOTIFICATIONS permissions (INTERNET is debug-only by default!)
 - OAuth deep link io.cnhs.portal://login-callback
 - Google Services gradle plugin (Kotlin or Groovy DSL)
"""
import pathlib, re, sys

A = pathlib.Path("android")
GMS = "4.4.2"

# 1. package name
for p in A.rglob("*"):
    if p.is_file() and p.suffix in {".kts", ".gradle", ".kt", ".java", ".xml"}:
        t = p.read_text()
        n = t.replace("io.cnhs.cnhs_portal", "io.cnhs.portal")
        if n != t:
            p.write_text(n)

# 2. manifest
m = A / "app/src/main/AndroidManifest.xml"
t = m.read_text()
if "android.permission.INTERNET" not in t:
    t = t.replace("<application",
        '<uses-permission android:name="android.permission.INTERNET"/>\n'
        '    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n'
        '    <application', 1)
if "login-callback" not in t:
    intent = ('\n            <intent-filter>\n'
              '                <action android:name="android.intent.action.VIEW"/>\n'
              '                <category android:name="android.intent.category.DEFAULT"/>\n'
              '                <category android:name="android.intent.category.BROWSABLE"/>\n'
              '                <data android:scheme="io.cnhs.portal" android:host="login-callback"/>\n'
              '            </intent-filter>\n        ')
    i = t.index("</activity>")
    t = t[:i].rstrip() + intent + t[i:]
m.write_text(t)

# 3. google-services plugin
def patch(path_kts, path_groovy, is_settings):
    for p, kotlin in ((A / path_kts, True), (A / path_groovy, False)):
        if not p.exists():
            continue
        t = p.read_text()
        if "com.google.gms.google-services" in t:
            return True
        if is_settings:
            # add next to the android application plugin declaration
            pat = re.compile(r'^(\s*)id\((["\'])com\.android\.application\2\)\s*version\s*(["\'][^"\']+["\'])\s*apply\s*false\s*$' if kotlin
                             else r'^(\s*)id\s+(["\'])com\.android\.application\2\s+version\s+(["\'][^"\']+["\'])\s+apply\s+false\s*$', re.M)
            mm = pat.search(t)
            if not mm:
                sys.exit(f"cannot find com.android.application in {p}")
            ind = mm.group(1)
            line = (f'{ind}id("com.google.gms.google-services") version "{GMS}" apply false' if kotlin
                    else f"{ind}id 'com.google.gms.google-services' version '{GMS}' apply false")
            t = t[:mm.end()] + "\n" + line + t[mm.end():]
        else:
            pat = re.compile(r'^(\s*)id\(?\s*(["\'])com\.android\.application\2\s*\)?\s*$', re.M)
            mm = pat.search(t)
            if not mm:
                sys.exit(f"cannot find com.android.application in {p}")
            ind = mm.group(1)
            line = (f'{ind}id("com.google.gms.google-services")' if kotlin
                    else f"{ind}id 'com.google.gms.google-services'")
            t = t[:mm.end()] + "\n" + line + t[mm.end():]
        p.write_text(t)
        return True
    return False

ok1 = patch("settings.gradle.kts", "settings.gradle", True)
ok2 = patch("app/build.gradle.kts", "app/build.gradle", False)
if not (ok1 and ok2):
    sys.exit("could not patch gradle files")
print("android patched")
