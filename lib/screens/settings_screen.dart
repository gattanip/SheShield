import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_settings/app_settings.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  // Permission states
  bool _locationPermission = false;
  bool _backgroundLocationPermission = false;
  bool _notificationPermission = false;
  bool _smsPermission = false;
  bool _contactsPermission = false;

  // Audio settings
  bool _emergencySoundEnabled = true;
  bool _alertSoundEnabled = true;
  bool _vibrationEnabled = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _emergencySoundEnabled = prefs.getBool('emergency_sound_enabled') ?? true;
      _alertSoundEnabled = prefs.getBool('alert_sound_enabled') ?? true;
      _vibrationEnabled = prefs.getBool('vibration_enabled') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('emergency_sound_enabled', _emergencySoundEnabled);
    await prefs.setBool('alert_sound_enabled', _alertSoundEnabled);
    await prefs.setBool('vibration_enabled', _vibrationEnabled);
  }

  Future<void> _checkPermissions() async {
    final locationStatus = await Permission.location.status;
    final backgroundLocationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;
    final smsStatus = await Permission.sms.status;
    final contactsStatus = await Permission.contacts.status;

    setState(() {
      _locationPermission = locationStatus.isGranted;
      _backgroundLocationPermission = backgroundLocationStatus.isGranted;
      _notificationPermission = notificationStatus.isGranted;
      _smsPermission = smsStatus.isGranted;
      _contactsPermission = contactsStatus.isGranted;
    });
  }

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.request();
    if (status.isGranted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Permission granted')),
      );
    } else if (status.isPermanentlyDenied) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Permission permanently denied. Please enable in settings.'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => AppSettings.openAppSettings(),
          ),
        ),
      );
    }
    _checkPermissions();
  }

  Widget _buildPermissionTile({
    required String title,
    required String description,
    required bool isGranted,
    required Permission permission,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: isGranted ? Colors.green : Colors.red),
      title: Text(title),
      subtitle: Text(description),
      trailing: Switch(
        value: isGranted,
        onChanged: (value) {
          if (value) {
            _requestPermission(permission);
          } else {
            AppSettings.openAppSettings();
          }
        },
      ),
    );
  }

  Widget _buildAudioSettingTile({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    required IconData icon,
  }) {
    return ListTile(
      leading: Icon(icon, color: value ? Colors.green : Colors.grey),
      title: Text(title),
      subtitle: Text(description),
      trailing: Switch(
        value: value,
        onChanged: (newValue) {
          setState(() {
            onChanged(newValue);
          });
          _saveSettings();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Permissions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
            _buildPermissionTile(
              title: 'Location',
              description: 'Required for emergency location tracking',
              isGranted: _locationPermission,
              permission: Permission.location,
              icon: Icons.location_on,
            ),
            _buildPermissionTile(
              title: 'Background Location',
              description: 'Required for continuous location tracking',
              isGranted: _backgroundLocationPermission,
              permission: Permission.locationAlways,
              icon: Icons.location_searching,
            ),
            _buildPermissionTile(
              title: 'Notifications',
              description: 'Required for emergency alerts',
              isGranted: _notificationPermission,
              permission: Permission.notification,
              icon: Icons.notifications,
            ),
            _buildPermissionTile(
              title: 'SMS',
              description: 'Required for sending emergency messages',
              isGranted: _smsPermission,
              permission: Permission.sms,
              icon: Icons.sms,
            ),
            _buildPermissionTile(
              title: 'Contacts',
              description: 'Required for emergency contacts',
              isGranted: _contactsPermission,
              permission: Permission.contacts,
              icon: Icons.contacts,
            ),
            const Divider(),
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: Text(
                'Audio & Vibration',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: Colors.red,
                ),
              ),
            ),
            _buildAudioSettingTile(
              title: 'Emergency Sound',
              description: 'Play sound during emergency alerts',
              value: _emergencySoundEnabled,
              onChanged: (value) => _emergencySoundEnabled = value,
              icon: Icons.volume_up,
            ),
            _buildAudioSettingTile(
              title: 'Alert Sound',
              description: 'Play sound for other notifications',
              value: _alertSoundEnabled,
              onChanged: (value) => _alertSoundEnabled = value,
              icon: Icons.notifications_active,
            ),
            _buildAudioSettingTile(
              title: 'Vibration',
              description: 'Vibrate for notifications and alerts',
              value: _vibrationEnabled,
              onChanged: (value) => _vibrationEnabled = value,
              icon: Icons.vibration,
            ),
            const SizedBox(height: 20),
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                'Note: Some permissions are required for the app to function properly. Disabling them may affect the app\'s ability to provide emergency services.',
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
} 