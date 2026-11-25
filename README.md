# TMKOC NoAds

Flutter-based TMKOC episode browser and player.

## Build

This repository intentionally keeps the platform scaffolding minimal. Generate Android files with:

```bash
flutter create --platforms=android .
flutter pub get
flutter build apk --debug
```

APK output: `build/app/outputs/flutter-apk/app-debug.apk`

## Player updates in this source package

- Immersive fullscreen with landscape orientation and Back-to-exit behavior.
- FIT / FILL video scaling.
- Previous / Next episode controls using the complete fetched episode list.
- Five-second Up Next countdown after playback completion, with Play now and Cancel.

The repository's GitHub Actions workflow also generates Android scaffolding before building.
