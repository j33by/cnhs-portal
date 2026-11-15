"""Run after `flutter create` in CI: makes the generated platform projects match what the app needs."""
import pathlib, re, sys
plat = sys.argv[1]
if plat == 'android':
    m = pathlib.Path('android/app/src/main/AndroidManifest.xml'); s = m.read_text()
    if 'permission.INTERNET' not in s:        # release builds have NO internet permission by default
        s = s.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>\n    <application', 1)
    if 'login-callback' not in s:             # Google sign-in returns to io.cnhs.portal://login-callback
        s = s.replace('</activity>', '''<intent-filter>
                <action android:name="android.intent.action.VIEW"/>
                <category android:name="android.intent.category.DEFAULT"/>
                <category android:name="android.intent.category.BROWSABLE"/>
                <data android:scheme="io.cnhs.portal" android:host="login-callback"/>
            </intent-filter>
        </activity>''', 1)
    s = re.sub(r'android:label="[^"]*"', 'android:label="CNHS Portal"', s, count=1)
    m.write_text(s)
    for g in ('android/app/build.gradle.kts', 'android/app/build.gradle'):   # Firebase needs minSdk 23
        p = pathlib.Path(g)
        if p.exists(): p.write_text(p.read_text().replace('flutter.minSdkVersion', '23'))
elif plat == 'windows':
    p = pathlib.Path('windows/runner/main.cpp')
    if p.exists(): p.write_text(p.read_text().replace('L"cnhs_portal"', 'L"CNHS Portal"'))
print('patched', plat)
