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

## Getting Started

### Prerequisites

- Flutter SDK (latest stable version)
- Dart SDK (latest stable version)
- Firebase project setup
- Android Studio / VS Code
- Physical device or emulator for testing

### Installation

1. Clone the repository:
```bash
git clone https://github.com/gattanip/SheShield.git
cd SheShield
```

2. Install dependencies:
```bash
flutter pub get
```

3. Configure Firebase:
   - Create a new Firebase project
   - Add Android and iOS apps to your Firebase project
   - Download and add the configuration files:
     - `google-services.json` for Android
     - `GoogleService-Info.plist` for iOS
   - Enable Firebase services (Firestore, Authentication)

4. Run the app:
```bash
flutter run
```

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