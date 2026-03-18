# Rhemacast Build Commands

## Android

### Debug
```
flutter build apk --debug
```

### Release
```
flutter build apk --release
```

> Note: Release builds require `android/key.properties` to be configured.
> See `android/key.properties.template` for the required fields.

## iOS

### Debug (no code signing)
```
flutter build ios --debug --no-codesign
```

### Release (IPA for App Store)
```
flutter build ipa
```

> Note: Release IPA builds require a valid Apple Developer account, provisioning
> profile, and code signing certificate configured in Xcode.
