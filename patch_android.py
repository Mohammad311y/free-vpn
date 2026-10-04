"""Patches the generated Android project for the Xray core (flutter_v2ray)."""
import pathlib, re

app = pathlib.Path('android/app')
for name, block in [('build.gradle', 'packagingOptions'), ('build.gradle.kts', 'packaging')]:
    g = app / name
    if not g.exists():
        continue
    t = g.read_text()
    t = re.sub(r'minSdk(Version)?\s*=?\s*flutter\.minSdkVersion', 'minSdk = 21', t)
    if 'useLegacyPackaging' not in t:
        t = t.replace('android {', 'android {\n    %s {\n        jniLibs {\n            useLegacyPackaging = true\n        }\n    }\n' % block, 1)
    g.write_text(t)
    print('patched', g)

m = app / 'src/main/AndroidManifest.xml'
t = m.read_text()
if 'android.permission.INTERNET' not in t:
    t = t.replace('<application', '<uses-permission android:name="android.permission.INTERNET"/>\n    <application', 1)
t = re.sub(r'android:label="[^"]*"', 'android:label="FreeVPN"', t, count=1)
m.write_text(t)
print('patched', m)
