# TMKOC NoAds

Flutter source for the TMKOC episode browser/player.

## Added in this update
- Player: muxed-stream quality selector (only qualities returned by source), left-side brightness swipe, right-side volume swipe, fullscreen/landscape, FIT/FILL, speed and seek controls.
- Playback position saved locally per episode and resumed on next open.
- Next/Previous navigation and 5-second Up Next prompt.
- On episode switch, pause and stop the previous media source before resolving/opening the next stream to prevent audio overlap.
- Home: watch history, continue-watching based on saved playback position, recently-added row, grid/list toggle, cached thumbnails with a decode-size hint.

## Build
This source archive does not include generated Android platform scaffolding. In a Flutter environment:
```bash
flutter create --platforms=android .
flutter pub get
flutter analyze
flutter build apk --debug
```

## Important verification
This environment did not have the Flutter SDK, Android SDK, or device runtime available. Run `flutter pub get`, `flutter analyze`, and a real-device playback test before replacing the installed APK. The quality list depends on the stream source providing muxed quality variants. Network throughput indicator is not yet implemented in this source revision; it should be added only with a reliable measurement source rather than displaying a misleading estimate.
