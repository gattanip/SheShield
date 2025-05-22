import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:app_settings/app_settings.dart';
import 'dart:async';
import '../services/emergency_media_service.dart';
import '../services/emergency_service.dart';
import 'package:url_launcher/url_launcher.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final EmergencyService _emergencyService = EmergencyService();
  StreamSubscription? _settingsSubscription;

  // Permission states
  bool _locationPermission = false;
  bool _backgroundLocationPermission = false;
  bool _notificationPermission = false;
  bool _smsPermission = false;
  bool _contactsPermission = false;
  bool _cameraPermission = false;
  bool _microphonePermission = false;
  bool _storagePermission = false;

  // Emergency settings
  String _defaultCaptureStrategy = 'balanced';
  bool _emergencySoundEnabled = true;
  bool _alertSoundEnabled = true;
  bool _vibrationEnabled = true;
  bool _autoUploadEnabled = true;
  bool _lowBatteryModeEnabled = false;

  // Media capture settings
  bool _frontCameraEnabled = true;
  bool _rearCameraEnabled = true;
  bool _audioCaptureEnabled = true;
  bool _videoCaptureEnabled = true;
  bool _photoCaptureEnabled = true;

  // Google Drive link
  TextEditingController _driveLinkController = TextEditingController();
  bool _isSavingDriveLink = false;
  String? _driveLinkError;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
    _loadDriveLink();
    _ensureFrontCameraEnabled();
    _setupSettingsListener();
  }

  void _setupSettingsListener() {
    _settingsSubscription?.cancel();
    _settingsSubscription = _emergencyService.settingsStream.listen((settings) {
      if (mounted) {
        setState(() {
          _emergencySoundEnabled = settings['emergencySound'] ?? true;
          _alertSoundEnabled = settings['alertSound'] ?? true;
          _vibrationEnabled = settings['vibration'] ?? true;
        });
      }
    });
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _autoUploadEnabled = prefs.getBool('auto_upload_enabled') ?? true;
      _lowBatteryModeEnabled = prefs.getBool('low_battery_mode_enabled') ?? false;
      _defaultCaptureStrategy = prefs.getString('default_capture_strategy') ?? 'balanced';
      _frontCameraEnabled = prefs.getBool('front_camera_enabled') ?? true;
      _rearCameraEnabled = prefs.getBool('rear_camera_enabled') ?? true;
      _audioCaptureEnabled = prefs.getBool('audio_capture_enabled') ?? true;
      _videoCaptureEnabled = prefs.getBool('video_capture_enabled') ?? true;
      _photoCaptureEnabled = prefs.getBool('photo_capture_enabled') ?? true;
    });
  }

  Future<void> _saveSettings() async {
    // Save permissions and other visible settings
    await _checkPermissions();
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Settings saved successfully'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> _checkPermissions() async {
    final locationStatus = await Permission.location.status;
    final backgroundLocationStatus = await Permission.locationAlways.status;
    final notificationStatus = await Permission.notification.status;
    final smsStatus = await Permission.sms.status;
    final contactsStatus = await Permission.contacts.status;
    final cameraStatus = await Permission.camera.status;
    final microphoneStatus = await Permission.microphone.status;
    final storageStatus = await Permission.storage.status;

    setState(() {
      _locationPermission = locationStatus.isGranted;
      _backgroundLocationPermission = backgroundLocationStatus.isGranted;
      _notificationPermission = notificationStatus.isGranted;
      _smsPermission = smsStatus.isGranted;
      _contactsPermission = contactsStatus.isGranted;
      _cameraPermission = cameraStatus.isGranted;
      _microphonePermission = microphoneStatus.isGranted;
      _storagePermission = storageStatus.isGranted;
    });
  }

  Future<void> _requestPermission(Permission permission) async {
    final status = await permission.request();
    await _checkPermissions();
    
    if (!status.isGranted && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${permission.toString().split('.').last} permission is required'),
          action: SnackBarAction(
            label: 'Settings',
            onPressed: () => AppSettings.openAppSettings(),
          ),
        ),
      );
    }
  }

  Widget _buildPermissionTile({
    required String title,
    required String description,
    required bool isGranted,
    required Permission permission,
    required IconData icon,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: Icon(
          icon,
          color: isGranted ? Colors.green : iconColor ?? Colors.grey,
        ),
        title: Text(title),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Switch(
          value: isGranted,
          onChanged: (value) => _requestPermission(permission),
          activeColor: Colors.green,
        ),
      ),
    );
  }

  Widget _buildSettingTile({
    required String title,
    required String description,
    required bool value,
    required ValueChanged<bool> onChanged,
    IconData? icon,
    Color? iconColor,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: ListTile(
        leading: icon != null
            ? Icon(icon, color: iconColor ?? Colors.grey)
            : null,
        title: Text(title),
        subtitle: Text(
          description,
          style: const TextStyle(fontSize: 12),
        ),
        trailing: Switch(
          value: value,
          onChanged: (newValue) {
            onChanged(newValue);
            // Save settings immediately when toggled
            _saveSettings();
          },
          activeColor: Colors.green,
        ),
      ),
    );
  }

  Future<void> _loadDriveLink() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString('emergency_drive_link');
    if (link != null) {
      setState(() {
        _driveLinkController.text = link;
      });
    }
  }

  Future<void> _saveDriveLink() async {
    setState(() {
      _isSavingDriveLink = true;
      _driveLinkError = null;
    });
    final link = _driveLinkController.text.trim();
    if (link.isEmpty || !link.contains('drive.google.com')) {
      setState(() {
        _driveLinkError = 'Please enter a valid Google Drive folder link';
        _isSavingDriveLink = false;
      });
      return;
    }
    try {
      final service = EmergencyMediaService();
      await service.setDriveFolderLink(link);
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('emergency_drive_link', link);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Drive link saved!'), backgroundColor: Colors.green),
        );
      }
    } catch (e) {
      setState(() {
        _driveLinkError = 'Failed to save link: $e';
      });
    } finally {
      setState(() {
        _isSavingDriveLink = false;
      });
    }
  }

  void _openDriveHelp() async {
    const url = 'https://support.google.com/drive/answer/7166529';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  Future<void> _ensureFrontCameraEnabled() async {
    final prefs = await SharedPreferences.getInstance();
    if (!prefs.containsKey('front_camera_enabled')) {
      await prefs.setBool('front_camera_enabled', true);
      setState(() {
        _frontCameraEnabled = true;
      });
    }
  }

  @override
  void dispose() {
    _settingsSubscription?.cancel();
    _driveLinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.save),
            onPressed: _saveSettings,
            tooltip: 'Save Settings',
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Permissions',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
            _buildPermissionTile(
              title: 'Location',
              description: 'Required for emergency location sharing',
              isGranted: _locationPermission,
              permission: Permission.location,
              icon: Icons.location_on,
              iconColor: Colors.blue,
            ),
            _buildPermissionTile(
              title: 'Camera',
              description: 'Required for emergency photo and video capture',
              isGranted: _cameraPermission,
              permission: Permission.camera,
              icon: Icons.camera_alt,
              iconColor: Colors.purple,
            ),
            _buildPermissionTile(
              title: 'Microphone',
              description: 'Required for emergency audio recording',
              isGranted: _microphonePermission,
              permission: Permission.microphone,
              icon: Icons.mic,
              iconColor: Colors.orange,
            ),
            _buildPermissionTile(
              title: 'Notifications',
              description: 'Required for emergency alerts',
              isGranted: _notificationPermission,
              permission: Permission.notification,
              icon: Icons.notifications,
              iconColor: Colors.red,
            ),
            _buildPermissionTile(
              title: 'SMS',
              description: 'Required for emergency SMS alerts',
              isGranted: _smsPermission,
              permission: Permission.sms,
              icon: Icons.sms,
              iconColor: Colors.blue,
            ),
            _buildPermissionTile(
              title: 'Contacts',
              description: 'Required for emergency contact access',
              isGranted: _contactsPermission,
              permission: Permission.contacts,
              icon: Icons.contacts,
              iconColor: Colors.purple,
            ),
            // Emergency settings and Media capture settings sections are hidden
            // but their functionality remains in the backend
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }
} 