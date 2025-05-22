# SheShield

A Flutter-based emergency alert and location tracking application designed to enhance personal safety.

## Features

- Real-time location tracking
- Emergency alert system with WhatsApp integration
- Background location updates
- High-accuracy location monitoring
- Emergency audio alerts
- Settings management for permissions and alerts
- Live tracking web interface

## Setup Instructions

### 1. Prerequisites
- [Flutter SDK](https://flutter.dev/docs/get-started/install) (latest stable)
- Android Studio or Xcode (for building on Android/iOS)
- A valid keystore for Android release builds
- Your own Firebase/Google Services configuration files (e.g., `google-services.json`, `GoogleService-Info.plist`)

### 2. Downloading the Project
- Clone the repository:
  ```
  git clone https://github.com/gattanip/SheShield.git
  cd SheShield
  ```

### 3. After Downloading
- Run `flutter pub get` to fetch dependencies.
- Place your Firebase/Google config files:
  - `android/app/google-services.json`
  - `ios/Runner/GoogleService-Info.plist`
- (Optional) Update app icons in `assets/icons/app_icon.png` and run:
  ```
  flutter pub run flutter_launcher_icons
  ```
- For Android release builds, provide your own keystore and update `android/key.properties`:
  ```
  storePassword=your_keystore_password
  keyPassword=your_key_password
  keyAlias=your_key_alias
  storeFile=your_keystore_file.keystore
  ```
- **Do NOT commit your keys, passwords, or config files to git.**

### 4. Building the App
- For Android APK:
  ```
  flutter build apk --release
  ```
- For iOS:
  ```
  flutter build ios --release
  ```

## Required Keys/Configs (NOT included in repo)
- `android/app/google-services.json` (Firebase Android config)
- `ios/Runner/GoogleService-Info.plist` (Firebase iOS config)
- `android/app/sheshield.keystore` (Android signing keystore)
- `android/key.properties` (Keystore config)

## Security
- Sensitive files are excluded via `.gitignore`:
  - Keystore files
  - Key properties
  - Firebase/Google config files
  - Any `.json` or `.env` secrets
- **Never share your keys or passwords publicly.**

## Support
For issues, open a GitHub issue or contact the maintainer.

## Configuration

### Required Permissions

- Location permission (while in use and background)
- Notification permission
- SMS permission (for emergency alerts)
- Contacts permission (for emergency contacts)

### Firebase Setup

1. Create a new Firebase project
2. Enable Firestore Database
3. Set up security rules
4. Add your app to the Firebase project
5. Download and add the configuration files

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/AmazingFeature`)
3. Commit your changes (`git commit -m 'Add some AmazingFeature'`)
4. Push to the branch (`git push origin feature/AmazingFeature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Flutter team for the amazing framework
- Firebase for backend services
- Geolocator package for location services
- All contributors and supporters of the project 