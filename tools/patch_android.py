import glob
import re

# 1) Manifest: permissions + audio service
p = 'android/app/src/main/AndroidManifest.xml'
s = open(p, encoding='utf-8').read()

perms = '''
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WAKE_LOCK"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE"/>
    <uses-permission android:name="android.permission.FOREGROUND_SERVICE_MEDIA_PLAYBACK"/>
    <uses-permission android:name="android.permission.POST_NOTIFICATIONS"/>
'''

services = '''
        <service android:name="com.ryanheise.audioservice.AudioService"
            android:foregroundServiceType="mediaPlayback"
            android:exported="true">
            <intent-filter>
                <action android:name="android.media.browse.MediaBrowserService"/>
            </intent-filter>
        </service>
        <receiver android:name="com.ryanheise.audioservice.MediaButtonReceiver"
            android:exported="true">
            <intent-filter>
                <action android:name="android.intent.action.MEDIA_BUTTON"/>
            </intent-filter>
        </receiver>
'''

if 'MANAGE_EXTERNAL_STORAGE' not in s:
    s = s.replace('<application', perms + '<application', 1)
    s = s.replace('</application>', services + '</application>', 1)

s = re.sub(r'android:label="[^"]*"', 'android:label="All in One"', s, count=1)
open(p, 'w', encoding='utf-8').write(s)

# 2) MainActivity must extend AudioServiceActivity
kt = '''package com.islamws.all_in_one

import com.ryanheise.audioservice.AudioServiceActivity

class MainActivity : AudioServiceActivity()
'''
for f in glob.glob('android/app/src/main/**/MainActivity.kt', recursive=True):
    open(f, 'w', encoding='utf-8').write(kt)
    print('patched', f)
