import 'package:flutter/material.dart';
import 'package:shared_preferences.dart';
import '../services/emergency_media_service.dart';
import 'package:url_launcher/url_launcher.dart';

class WelcomeDriveSetupScreen extends StatefulWidget {
  const WelcomeDriveSetupScreen({super.key});

  @override
  State<WelcomeDriveSetupScreen> createState() => _WelcomeDriveSetupScreenState();
}

class _WelcomeDriveSetupScreenState extends State<WelcomeDriveSetupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _driveLinkController = TextEditingController();
  final _emergencyService = EmergencyMediaService();
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _loadExistingDriveLink();
  }

  Future<void> _loadExistingDriveLink() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final link = prefs.getString('emergency_drive_link');
      if (link != null) {
        _driveLinkController.text = link;
      }
    } catch (e) {
      print('❌ [WelcomeDrive] Error loading drive link: $e');
    }
  }

  Future<void> _saveDriveLink() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final link = _driveLinkController.text.trim();
      await _emergencyService.setDriveFolderLink(link);
      
      if (mounted) {
        Navigator.of(context).pop(true); // Return success
      }
    } catch (e) {
      setState(() {
        _errorMessage = e.toString();
      });
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  Future<void> _openDriveHelp() async {
    const url = 'https://support.google.com/drive/answer/7166529';
    if (await canLaunchUrl(Uri.parse(url))) {
      await launchUrl(Uri.parse(url));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Welcome to SheShield'),
        automaticallyImplyLeading: false,
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
          padding: const EdgeInsets.all(16.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.cloud_upload,
                  size: 80,
                  color: Colors.blue,
                ),
                const SizedBox(height: 24),
                const Text(
                  'Welcome to SheShield',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                const Text(
                  'Your safety is our priority.',
                  style: TextStyle(fontSize: 16),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _driveLinkController.dispose();
    super.dispose();
  }
} 