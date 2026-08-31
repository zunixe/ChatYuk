#!/bin/bash

# Update Play Store listing URL dan Privacy Policy

# 1. Update app bundle metadata
flutter clean
flutter build appbundle --release --flavor play --dart-define=APP_FLAVOR=play

# 2. Update Play Console Data Safety (manual)
# Buka: https://play.google.com/console/u/1/developers/8359197228304141922/app/4974318379582736850/app-content/data-privacy-security
# Isi form sesuai panduan di play_console_data_safety_guide.md

# 3. Update Privacy Policy link di app
# Edit lib/config/strings.dart - tambahkan privacy policy URL
# Edit AndroidManifest.xml - tambahkan metadata untuk privacy policy

# 4. Submit ke Google Play
# Gunakan fastlane: fastlane play track:alpha

echo "=== Update Play Store Listing ==="
echo "1. Build AAB untuk Play:"
flutter build appbundle --release --flavor play --dart-define=APP_FLAVOR=play

echo "2. Update Data Safety form manually:"
echo "   - Buka URL di atas"
echo "   - Isi form sesuai panduan"
echo "   - Verifikasi dengan dart verify_data_collection.dart"

echo "3. Upload AAB:"
fastlane play track:alpha

echo "=== Done! ==="
