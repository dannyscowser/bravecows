# Brave Cows - Chinese character study app

Flutter app that bundles a CC-CEDICT + SUBTLEX-CH SQLite database for offline browsing and a lightweight review loop.

Features
- Offline dictionary (trad/simp/pinyin/definitions + frequency).
- Multiple study lists (create/switch via Home or add-to-list sheets); simple SRS rule (known = last 4 reviews correct).
- Screens: Home (due count + quick links), Review (flip-card flow), Collection Book (frequency-ordered unique characters), Character Detail, Search (FTS, de-duped), Learn (random or banded high-frequency batches), Zi-Dex (known stats/grid), Licenses.
- Script toggle (Traditional/Simplified) applied across the app.

Getting started
1) Prerequisites
- Install Flutter: https://flutter.dev/docs/get-started/install
- On macOS: install Xcode (for iOS simulator) and CocoaPods.
  - Install CocoaPods: `brew install cocoapods` (if not already installed)
  - After Xcode install run: `sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer` and `sudo xcodebuild -runFirstLaunch`

2) Prepare the project
```
cd "/Users/dannyc/Documents/Apps/Brave Cow/brave_cows_app"
flutter pub get
```

3) Assets
- The app expects `assets/db/hanzi.sqlite` (already bundled) and an image at `assets/cows_dayin.png`.

4) iOS setup (macOS only)
If you plan to run on the iOS simulator or a device:
```
cd ios
pod install
cd ..
```

5) Run the app
- To run on the first available device/emulator:
  ```
  flutter run
  ```
- To run tests:
  ```
  flutter test
  ```

Project structure (key files)
- lib/main.dart — app entry and provider wiring
- lib/models/character.dart — Character model
- lib/models/study_list.dart — Study list info
- lib/providers/hanzi_provider.dart — Provider for study/review/lists
- lib/services/db_service.dart — SQLite bootstrap + queries
- lib/screens/* — UI screens (home, review, collection, detail, search, learn, zi-dex, licenses)
- assets/db/hanzi.sqlite — bundled dictionary data

Notes
- Study list is empty on first launch; add characters from Search or Collection to get review cards.
- Learn offers weighted batches or 100-character frequency bands; the bundled Anki deck is available as a list, and only characters not already in any list are suggested.
- Reviews and study data live in the writable copy of the bundled SQLite DB.
- Zi-Dex shows known characters (known = last 4 reviews correct) and simple frequency-band stats; Collection Book lists unique characters ordered by frequency.

License
MIT
