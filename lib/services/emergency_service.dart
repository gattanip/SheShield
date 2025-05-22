import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../models/contact.dart';
import '../models/emergency_state.dart';
import 'location_service.dart';
import 'package:url_launcher/url_launcher.dart';
import 'location_tracking_service.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'emergency_audio_service.dart';
import 'package:flutter/material.dart';
import 'dart:async';
import 'logging_service.dart';
import 'package:whatsapp_unilink/whatsapp_unilink.dart';
import 'emergency_media_service.dart';
import 'package:uuid/uuid.dart';

class EmergencyService {
  static final EmergencyService _instance = EmergencyService._internal();
  factory EmergencyService() => _instance;
  EmergencyService._internal() {
    // Initialize state restoration in constructor
    _initializeStateRestoration();
  }

  static const platform = MethodChannel('com.SheShield.app/emergency');
  static const String _contactsKey = 'emergency_contacts';
  
  // Initialize all services in constructor
  late final LocationService _locationService;
  late final LocationTrackingService _locationTracking;
  late final EmergencyMediaService _mediaService;
  late final NetworkService _networkService;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final EmergencyAudioService _audioService = EmergencyAudioService();
  final LoggingService _logger = LoggingService();

  // Add initialization status tracking
  bool _isLocationServiceInitialized = false;
  bool _isLocationTrackingInitialized = false;
  bool _isMediaServiceInitialized = false;
  bool _isNetworkServiceInitialized = false;

  bool _isInitialized = false;
  bool _isEmergencyActive = false;
  bool _messageSent = false;
  Timer? _statusCheckTimer;
  String? _emergencyId;
  Timer? _cleanupTimer;

  // Audio settings
  bool _emergencySoundEnabled = true;
  bool _alertSoundEnabled = true;
  bool _vibrationEnabled = true;

  // Add settings keys
  static const String _emergencySoundKey = 'emergency_sound_enabled';
  static const String _alertSoundKey = 'alert_sound_enabled';
  static const String _vibrationKey = 'vibration_enabled';

  // Update the StreamController type to accept dynamic values
  final StreamController<Map<String, dynamic>> _settingsController = StreamController<Map<String, dynamic>>.broadcast();
  Stream<Map<String, dynamic>> get settingsStream => _settingsController.stream;

  bool get isInitialized => _isInitialized;
  bool get isEmergencyActive => _isEmergencyActive;
  bool get messageSent => _messageSent;

  static const Duration _initializationTimeout = Duration(seconds: 10);
  Timer? _initializationTimer;
  bool _isInitializing = false;
  String? _initializationError;
  StreamController<bool> _initializationController = StreamController<bool>.broadcast();
  StreamController<EmergencyState> _stateController = StreamController<EmergencyState>.broadcast();

  // Add getters for streams
  Stream<bool> get initializationStream => _initializationController.stream;
  Stream<EmergencyState> get stateStream => _stateController.stream;

  // Add back the current state field and getter
  EmergencyState _currentState = EmergencyState.initializing;
  EmergencyState get currentState => _currentState;

  // Add static instance getter for global access
  static EmergencyService get instance => _instance;

  // Emergency state persistence keys
  static const String _emergencyStateKey = 'emergency_state';
  static const String _emergencyIdKey = 'emergency_id';

  // Add state restoration initialization
  Future<void> _initializeStateRestoration() async {
    try {
      await _restoreEmergencyState();
      // Start periodic state verification
      _startStateVerificationTimer();
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error initializing state restoration', e);
    }
  }

  // Add periodic state verification
  Timer? _stateVerificationTimer;
  void _startStateVerificationTimer() {
    _stateVerificationTimer?.cancel();
    _stateVerificationTimer = Timer.periodic(const Duration(seconds: 5), (_) async {
      if (_isEmergencyActive) {
        await _verifyAndRestoreState();
      }
    });
  }

  // Add state verification and restoration
  Future<void> _verifyAndRestoreState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateStr = prefs.getString(_emergencyStateKey);
      final emergencyId = prefs.getString(_emergencyIdKey);

      // If state is active in storage but not in memory, restore it
      if (stateStr == EmergencyState.active.toString() && 
          emergencyId != null && 
          !_isEmergencyActive) {
        await _logger.log(LogLevel.info, 'EmergencyService', 'Restoring emergency state from storage');
        await _restoreEmergencyState();
      }
      // If state is active in memory but not in storage, persist it
      else if (_isEmergencyActive && 
               (stateStr != EmergencyState.active.toString() || 
                emergencyId != _emergencyId)) {
        await _logger.log(LogLevel.info, 'EmergencyService', 'Persisting emergency state to storage');
        await _persistEmergencyState();
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error verifying state', e);
    }
  }

  // Update persistEmergencyState to be more robust
  Future<void> _persistEmergencyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (_isEmergencyActive && _emergencyId != null) {
        await prefs.setString(_emergencyStateKey, _currentState.toString());
        await prefs.setString(_emergencyIdKey, _emergencyId!);
        await prefs.setBool('is_emergency_active', true);
        await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency state persisted');
      } else {
        await _clearPersistedState();
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error persisting emergency state', e);
    }
  }

  // Update clearPersistedState to be more thorough
  Future<void> _clearPersistedState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_emergencyStateKey);
      await prefs.remove(_emergencyIdKey);
      await prefs.remove('is_emergency_active');
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency state cleared from storage');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error clearing persisted state', e);
    }
  }

  // Restore emergency state
  Future<void> _restoreEmergencyState() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final stateStr = prefs.getString(_emergencyStateKey);
      final emergencyId = prefs.getString(_emergencyIdKey);
      
      if (stateStr == EmergencyState.active.toString() && emergencyId != null) {
        await _logger.log(LogLevel.info, 'EmergencyService', 'Restoring emergency state');
        
        // Verify services are running
        await _verifyEmergencyServices();
        
        _emergencyId = emergencyId;
        _isEmergencyActive = true;
        _currentState = EmergencyState.active;
        _stateController.add(_currentState);
        
        await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency state restored successfully');
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error restoring emergency state', e);
      // Clear persisted state if restoration fails
      await _clearPersistedState();
    }
  }

  // Verify emergency services are running
  Future<void> _verifyEmergencyServices() async {
    try {
      // Verify location tracking
      if (!await _locationTracking.isTrackingActive()) {
        await _locationTracking.startLocationSharing();
      }

      // Verify audio service if enabled
      if (_emergencySoundEnabled && !_audioService.isPlaying) {
        await _audioService.startEmergencySound();
      }

      // Verify media service if initialized
      if (_isMediaServiceInitialized && !_mediaService.isCapturing) {
        await _mediaService.startMediaCapture();
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error verifying emergency services', e);
      // Don't throw, just log the error
    }
  }

  // Get emergency contacts from storage
  Future<List<EmergencyContact>> getContacts() async {
    final prefs = await SharedPreferences.getInstance();
    final contactsJson = prefs.getStringList(_contactsKey) ?? [];
    return contactsJson
        .map((contact) => EmergencyContact.fromJson(json.decode(contact)))
        .toList();
  }

  // Save emergency contact
  Future<void> addContact(EmergencyContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();

    // Get the phone number and clean it
    String formattedNumber = contact.phoneNumber.trim();

    // If number doesn't start with +91, clean it and add +91
    if (!formattedNumber.startsWith('+91')) {
      // Remove all non-digit characters
      formattedNumber = formattedNumber.replaceAll(RegExp(r'\D'), '');
      
      // If it starts with 91, remove it first
      if (formattedNumber.startsWith('91')) {
        formattedNumber = formattedNumber.substring(2);
      }
      
      // Ensure it's 10 digits
      if (formattedNumber.length != 10) {
        throw Exception('Phone number must be 10 digits');
      }
      
      // Add +91 prefix
      formattedNumber = '+91$formattedNumber';
    }

    // Validate final format
    if (!RegExp(r'^\+91\d{10}$').hasMatch(formattedNumber)) {
      throw Exception('Invalid phone number format');
    }

    // Check for duplicates
    if (contacts.any((c) => c.phoneNumber == formattedNumber)) {
      throw Exception('Contact with this phone number already exists');
    }

    // Create formatted contact
    final formattedContact = EmergencyContact(
      name: contact.name.trim(),
      phoneNumber: formattedNumber,
      email: contact.email?.trim(),
    );

    // Add to contacts list and save
    contacts.add(formattedContact);
    final contactsJson = contacts.map((c) => json.encode(c.toJson())).toList();
    await prefs.setStringList(_contactsKey, contactsJson);

    await _logger.log(LogLevel.info, 'EmergencyService',
        'Added emergency contact: ${formattedContact.name} (${formattedContact.phoneNumber})');
  }

  // Remove emergency contact
  Future<void> removeContact(EmergencyContact contact) async {
    final prefs = await SharedPreferences.getInstance();
    final contacts = await getContacts();
    
    contacts.removeWhere((c) => c.phoneNumber == contact.phoneNumber);
    
    final contactsJson = contacts
        .map((contact) => json.encode(contact.toJson()))
        .toList();
    
    await prefs.setStringList(_contactsKey, contactsJson);
  }

  // Update initialize method to restore state
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _logger.initialize();
      await _logger.log(LogLevel.info, 'EmergencyService', 'Initializing emergency service...');

      // Initialize service instances
      _locationService = LocationService();
      _locationTracking = LocationTrackingService();
      _mediaService = EmergencyMediaService();
      _networkService = NetworkService();

      // Initialize services with timeout and retry logic
      int retryCount = 0;
      const maxRetries = 3;
      bool initializationSuccess = false;

      while (retryCount < maxRetries && !initializationSuccess) {
        try {
          // Initialize services sequentially with individual timeouts
          await _initializeServiceWithTimeout(
            _initializeLocationService(),
            'Location Service',
            const Duration(seconds: 15),
          );

          await _initializeServiceWithTimeout(
            _initializeLocationTracking(),
            'Location Tracking',
            const Duration(seconds: 15),
          );

          // Try to initialize media service, but don't fail if it doesn't work
          try {
            await _initializeServiceWithTimeout(
              _initializeMediaService(),
              'Media Service',
              const Duration(seconds: 15),
            );
          } catch (e) {
            await _logger.log(LogLevel.warning, 'EmergencyService', 
              'Media service initialization failed, continuing without media support: $e');
            _isMediaServiceInitialized = false;
          }

          await _initializeServiceWithTimeout(
            _initializeNetworkService(),
            'Network Service',
            const Duration(seconds: 15),
          );

          // Verify critical services are initialized
          if (!_isLocationServiceInitialized || !_isLocationTrackingInitialized) {
            throw Exception('Critical services (location) failed to initialize properly');
          }

          initializationSuccess = true;
        } catch (e) {
          retryCount++;
          await _logger.log(LogLevel.warning, 'EmergencyService', 
            'Service initialization attempt $retryCount failed: $e');
          
          if (retryCount == maxRetries) {
            throw Exception('Failed to initialize critical services after $maxRetries attempts: $e');
          }
          
          // Wait before retrying with exponential backoff
          await Future.delayed(Duration(seconds: 2 * retryCount));
          
          // Clean up any partially initialized services
          await _cleanupServices();
        }
      }

      // Restore emergency state after initialization
      await _restoreEmergencyState();

      _isInitialized = true;
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency service initialized successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Failed to initialize emergency service', e, stackTrace);
      await _cleanupServices();
      rethrow;
    }
  }

  Future<void> _initializeServiceWithTimeout(
    Future<void> serviceFuture,
    String serviceName,
    Duration timeout,
  ) async {
    try {
      await serviceFuture.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('$serviceName initialization timed out after ${timeout.inSeconds} seconds'),
      );
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error initializing $serviceName', e);
      rethrow;
    }
  }

  Future<void> _initializeLocationService() async {
    try {
      await _locationService.initialize();
      _isLocationServiceInitialized = true;
      await _logger.log(LogLevel.info, 'EmergencyService', 'Location service initialized successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Failed to initialize location service', e);
      rethrow;
    }
  }

  Future<void> _initializeLocationTracking() async {
    try {
      await _locationTracking.initialize();
      _isLocationTrackingInitialized = true;
      await _logger.log(LogLevel.info, 'EmergencyService', 'Location tracking initialized successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Failed to initialize location tracking', e);
      rethrow;
    }
  }

  Future<void> _initializeMediaService() async {
    try {
      await _mediaService.initialize();
      _isMediaServiceInitialized = true;
      await _logger.log(LogLevel.info, 'EmergencyService', 'Media service initialized successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Failed to initialize media service', e);
      rethrow;
    }
  }

  Future<void> _initializeNetworkService() async {
    try {
      await _networkService.initialize();
      _isNetworkServiceInitialized = true;
      await _logger.log(LogLevel.info, 'EmergencyService', 'Network service initialized successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Failed to initialize network service', e);
      rethrow;
    }
  }

  // Update startEmergency to persist state
  Future<void> startEmergency() async {
    if (_isEmergencyActive) {
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency already active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'EmergencyService', 'Starting emergency services...');
      _currentState = EmergencyState.starting;
      _stateController.add(_currentState);
      
      // Reload settings first to ensure we have the latest values
      await _loadSettings();
      
      // Start location tracking first
      try {
        await _startServiceWithTimeout(
          _locationTracking.startLocationSharing(),
          'Location Tracking',
          const Duration(seconds: 5),
        );
        await _logger.log(LogLevel.info, 'EmergencyService', 'Location tracking started successfully');
      } catch (e) {
        await _logger.log(LogLevel.error, 'EmergencyService', 'Error starting location tracking', e);
        rethrow;
      }
      
      // Start audio service only if enabled
      if (_emergencySoundEnabled) {
        try {
          await _startServiceWithTimeout(
            _audioService.startEmergencySound(),
            'Emergency Sound',
            const Duration(seconds: 5),
          );
          await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency sound started successfully');
        } catch (e) {
          await _logger.log(LogLevel.warning, 'EmergencyService', 'Error starting emergency sound, continuing without audio', e);
          // Continue emergency activation even if audio fails
        }
      } else {
        await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency sound disabled in settings, skipping audio');
      }

      // Start media capture if initialized
      if (_isMediaServiceInitialized) {
        try {
          await _startServiceWithTimeout(
            _mediaService.startMediaCapture(),
            'Media Capture',
            const Duration(seconds: 5),
          );
          await _logger.log(LogLevel.info, 'EmergencyService', 'Media capture started successfully');
        } catch (e) {
          await _logger.log(LogLevel.warning, 'EmergencyService', 'Error starting media capture, continuing without media', e);
          // Continue emergency activation even if media fails
        }
      }

      // Generate emergency ID and persist state
      _emergencyId = const Uuid().v4();
      await _persistEmergencyState();
      
      _isEmergencyActive = true;
      _currentState = EmergencyState.active;
      _stateController.add(_currentState);
      
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency services started successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error starting emergency services', e);
      _currentState = EmergencyState.error;
      _stateController.add(_currentState);
      rethrow;
    }
  }

  Future<void> _startServiceWithTimeout(
    Future<void> serviceFuture,
    String serviceName,
    Duration timeout,
  ) async {
    try {
      await serviceFuture.timeout(
        timeout,
        onTimeout: () => throw TimeoutException('$serviceName timed out after ${timeout.inSeconds} seconds'),
      );
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error starting $serviceName', e);
      rethrow;
    }
  }

  Future<void> _createEmergencyDocument() async {
    if (_emergencyId == null) return;

    try {
      final position = await _locationService.getCurrentPosition();
      final trackingUrl = await _locationTracking.getTrackingUrl();

      await _firestore.collection('emergencies').doc(_emergencyId).set({
        'status': 'active',
        'startedAt': FieldValue.serverTimestamp(),
        'location': {
          'latitude': position.latitude,
          'longitude': position.longitude,
          'accuracy': position.accuracy,
          'altitude': position.altitude,
          'speed': position.speed,
          'heading': position.heading,
          'timestamp': FieldValue.serverTimestamp(),
        },
        'trackingUrl': trackingUrl,
        'mediaSessionId': _mediaService.currentSessionId,
        'settings': {
          'emergencySound': _emergencySoundEnabled,
          'alertSound': _alertSoundEnabled,
          'vibration': _vibrationEnabled,
        },
      });

      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency document created successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error creating emergency document', e, stackTrace);
      rethrow;
    }
  }

  void _startStatusCheckTimer() {
    _statusCheckTimer?.cancel();
    _statusCheckTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      _checkEmergencyStatus();
    });
  }

  Future<void> _checkEmergencyStatus() async {
    if (!_isEmergencyActive || _emergencyId == null) return;

    try {
      final doc = await _firestore
          .collection('emergencies')
          .doc(_emergencyId)
          .get();

      if (!doc.exists || doc.data()?['status'] != 'active') {
        await _logger.log(LogLevel.warning, 'EmergencyService', 'Emergency status check failed, stopping services');
        await stopEmergency();
      }
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error checking emergency status', e, stackTrace);
    }
  }

  Future<void> sendEmergencyAlert(BuildContext context) async {
    try {
      debugPrint('Starting emergency alert...');
      _isEmergencyActive = true;
      _messageSent = false;

      // Get emergency contacts
      final contacts = await getContacts();
      if (contacts.isEmpty) {
        throw Exception('No emergency contacts found. Please add at least one emergency contact.');
      }

      // Reload settings in case they changed
      await _loadSettings();

      // Start location tracking first with retry logic
      debugPrint('Starting location tracking...');
      int retryCount = 0;
      const maxRetries = 3;
      bool trackingStarted = false;
      while (retryCount < maxRetries && !trackingStarted) {
        try {
          await _locationTracking.startLocationSharing();
          debugPrint('Location tracking started');
          trackingStarted = true;
        } catch (e) {
          retryCount++;
          debugPrint('Location tracking attempt $retryCount failed: $e');
          if (retryCount == maxRetries) {
            throw Exception('Failed to start location tracking after $maxRetries attempts: $e');
          }
          await Future.delayed(Duration(seconds: 2 * retryCount)); // Exponential backoff
        }
      }

      // Get current position for initial alert with retry logic
      debugPrint('Getting current position...');
      Position? position;
      retryCount = 0;
      while (retryCount < maxRetries && position == null) {
        try {
          position = await Geolocator.getCurrentPosition(
            desiredAccuracy: LocationAccuracy.high,
            timeLimit: const Duration(seconds: 10),
          );
          debugPrint('Current position: ${position.latitude}, ${position.longitude}');
        } catch (e) {
          retryCount++;
          debugPrint('Position attempt $retryCount failed: $e');
          if (retryCount == maxRetries) {
            throw Exception('Failed to get current position after $maxRetries attempts: $e');
          }
          await Future.delayed(Duration(seconds: 2 * retryCount));
        }
      }
      if (position == null) throw Exception('Could not get current position');

      // Send WhatsApp message to each emergency contact
      debugPrint('Preparing WhatsApp messages...');
      final message = '''
🚨 EMERGENCY ALERT 🚨
I need help! Please check my location:

🗺️ Current Location:
https://maps.google.com/?q=${position.latitude},${position.longitude}

⚠️ This is an automated emergency alert shared by SheShield App.
''';

      bool anyMessageSent = false;
      for (var contact in contacts) {
        try {
          String phoneNumber = contact.phoneNumber.replaceAll(RegExp(r'[^\d]'), '');
          if (phoneNumber.length == 10 && !phoneNumber.startsWith("91")) {
            phoneNumber = "91$phoneNumber";
          }
          
          final whatsappUrl = Uri.parse(
            'whatsapp://send?phone=$phoneNumber&text=${Uri.encodeComponent(message)}'
          );

          if (await canLaunchUrl(whatsappUrl)) {
            debugPrint('Launching WhatsApp for contact: ${contact.name}');
            await launchUrl(whatsappUrl);
            anyMessageSent = true;
            debugPrint('WhatsApp message sent successfully to ${contact.name}');
          } else {
            debugPrint('Could not launch WhatsApp for contact: ${contact.name}');
          }
        } catch (e) {
          debugPrint('Error sending message to ${contact.name}: $e');
        }
      }

      if (anyMessageSent) {
        _messageSent = true;
        debugPrint('Emergency messages sent to at least one contact');
      } else {
        throw Exception('Could not send messages to any emergency contacts');
      }

      // Create emergency document with tracking info
      debugPrint('Creating emergency document...');
      try {
        final emergencyDoc = await _firestore.collection('emergencies').add({
          'status': 'active',
          'startedAt': FieldValue.serverTimestamp(),
          'lastUpdate': FieldValue.serverTimestamp(),
          'messageSent': _messageSent,
          'location': {
            'latitude': position.latitude,
            'longitude': position.longitude,
            'accuracy': position.accuracy,
            'timestamp': position.timestamp?.toIso8601String(),
          },
          'settings': {
            'emergencySound': _emergencySoundEnabled,
            'alertSound': _alertSoundEnabled,
            'vibration': _vibrationEnabled,
          },
        });
        debugPrint('Emergency document created with ID: ${emergencyDoc.id}');
      } catch (e) {
        debugPrint('Error creating emergency document: $e');
        // Don't reset emergency state on document creation error
      }
    } catch (e) {
      debugPrint('Error in sendEmergencyAlert: $e');
      if (e.toString().contains('critical') || e.toString().contains('fatal')) {
        _isEmergencyActive = false;
        _messageSent = false;
      }
      rethrow;
    }
  }

  // Update stopEmergency to clear persisted state
  Future<void> stopEmergency() async {
    if (!_isEmergencyActive) {
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency not active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'EmergencyService', 'Stopping emergency services...');
      _currentState = EmergencyState.stopping;
      _stateController.add(_currentState);

      // Stop all services
      await Future.wait([
        _locationTracking.stopLocationSharing(),
        _audioService.stopEmergencySound(),
        if (_isMediaServiceInitialized) _mediaService.stopMediaCapture(),
      ]);

      // Clear persisted state first
      await _clearPersistedState();
      
      // Then update in-memory state
      _isEmergencyActive = false;
      _emergencyId = null;
      _currentState = EmergencyState.ready;
      _stateController.add(_currentState);
      
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency services stopped successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error stopping emergency services', e);
      _currentState = EmergencyState.error;
      _stateController.add(_currentState);
      rethrow;
    }
  }

  // Check if tracking is active
  Future<bool> isTrackingActive() async {
    return await _locationTracking.isTrackingActive();
  }

  // Update _loadSettings to use the new keys
  Future<void> _loadSettings() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      
      // Load settings with defaults
      _emergencySoundEnabled = prefs.getBool(_emergencySoundKey) ?? true;
      _alertSoundEnabled = prefs.getBool(_alertSoundKey) ?? true;
      _vibrationEnabled = prefs.getBool(_vibrationKey) ?? true;
      
      // Notify listeners of current settings
      _settingsController.add({
        'emergencySound': _emergencySoundEnabled,
        'alertSound': _alertSoundEnabled,
        'vibration': _vibrationEnabled,
      });
      
      await _logger.log(LogLevel.info, 'EmergencyService', 
        'Settings loaded: emergencySound=$_emergencySoundEnabled, alertSound=$_alertSoundEnabled, vibration=$_vibrationEnabled');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error loading settings', e);
      // Use defaults if loading fails
      _emergencySoundEnabled = true;
      _alertSoundEnabled = true;
      _vibrationEnabled = true;
    }
  }

  Future<bool> requestSMSPermissions() async {
    try {
      final bool result = await platform.invokeMethod('requestSMSPermissions');
      return result;
    } catch (e) {
      print('Error requesting SMS permissions: $e');
      return false;
    }
  }

  // Update dispose to clean up settings controller
  Future<void> dispose() async {
    try {
      _stateVerificationTimer?.cancel();
      await _cleanupServices();
      _settingsController.close();
      _isInitialized = false;
      await _logger.log(LogLevel.info, 'EmergencyService', 'Emergency service disposed');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error disposing emergency service', e);
    }
  }

  Future<void> _cleanupServices() async {
    try {
      // Call dispose methods without await since they return void
      _locationService.dispose();
      _mediaService.dispose();
      _networkService.dispose();
      
      // Reinitialize services
      _locationService = LocationService();
      _mediaService = EmergencyMediaService();
      _networkService = NetworkService();
      
      await _logger.log(LogLevel.info, 'EmergencyService', 'Services cleaned up and reinitialized');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error cleaning up services', e);
    }
  }

  // Add updateSettings method
  Future<void> updateSettings({
    required bool emergencySound,
    required bool alertSound,
    required bool vibration,
  }) async {
    try {
      // Update in-memory settings
      _emergencySoundEnabled = emergencySound;
      _alertSoundEnabled = alertSound;
      _vibrationEnabled = vibration;

      // Save to persistent storage
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(_emergencySoundKey, emergencySound);
      await prefs.setBool(_alertSoundKey, alertSound);
      await prefs.setBool(_vibrationKey, vibration);

      // Notify listeners
      _settingsController.add({
        'emergencySound': emergencySound,
        'alertSound': alertSound,
        'vibration': vibration,
      });

      await _logger.log(LogLevel.info, 'EmergencyService', 
        'Settings updated: emergencySound=$emergencySound, alertSound=$alertSound, vibration=$vibration');

      // If emergency is active, update audio service
      if (_isEmergencyActive) {
        if (emergencySound && !_audioService.isPlaying) {
          await _audioService.startEmergencySound();
        } else if (!emergencySound && _audioService.isPlaying) {
          await _audioService.stopEmergencySound();
        }
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyService', 'Error updating settings', e);
      rethrow;
    }
  }

  // Add static methods for programmatic settings access
  static Future<Map<String, dynamic>> getEmergencySettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'emergencySound': prefs.getBool(_emergencySoundKey) ?? true,
      'alertSound': prefs.getBool(_alertSoundKey) ?? true,
      'vibration': prefs.getBool(_vibrationKey) ?? true,
      'autoUpload': prefs.getBool('auto_upload_enabled') ?? true,
      'lowBatteryMode': prefs.getBool('low_battery_mode_enabled') ?? false,
      'defaultCaptureStrategy': prefs.getString('default_capture_strategy') ?? 'balanced',
    };
  }

  static Future<Map<String, dynamic>> getMediaCaptureSettings() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'frontCamera': prefs.getBool('front_camera_enabled') ?? true,
      'rearCamera': prefs.getBool('rear_camera_enabled') ?? true,
      'audioCapture': prefs.getBool('audio_capture_enabled') ?? true,
      'videoCapture': prefs.getBool('video_capture_enabled') ?? true,
      'photoCapture': prefs.getBool('photo_capture_enabled') ?? true,
    };
  }

  // Update the updateEmergencySettings method
  static Future<void> updateEmergencySettings({
    bool? emergencySound,
    bool? alertSound,
    bool? vibration,
    bool? autoUpload,
    bool? lowBatteryMode,
    String? defaultCaptureStrategy,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final updates = <String, dynamic>{};

    if (emergencySound != null) {
      await prefs.setBool(_emergencySoundKey, emergencySound);
      updates['emergencySound'] = emergencySound;
    }
    if (alertSound != null) {
      await prefs.setBool(_alertSoundKey, alertSound);
      updates['alertSound'] = alertSound;
    }
    if (vibration != null) {
      await prefs.setBool(_vibrationKey, vibration);
      updates['vibration'] = vibration;
    }
    if (autoUpload != null) {
      await prefs.setBool('auto_upload_enabled', autoUpload);
      updates['autoUpload'] = autoUpload;
    }
    if (lowBatteryMode != null) {
      await prefs.setBool('low_battery_mode_enabled', lowBatteryMode);
      updates['lowBatteryMode'] = lowBatteryMode;
    }
    if (defaultCaptureStrategy != null) {
      await prefs.setString('default_capture_strategy', defaultCaptureStrategy);
      updates['defaultCaptureStrategy'] = defaultCaptureStrategy;
    }

    // Update instance if it exists
    if (_instance._isInitialized) {
      _instance._settingsController.add(updates);
    }
  }

  // Update the updateMediaCaptureSettings method
  static Future<void> updateMediaCaptureSettings({
    bool? frontCamera,
    bool? rearCamera,
    bool? audioCapture,
    bool? videoCapture,
    bool? photoCapture,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final updates = <String, dynamic>{};

    if (frontCamera != null) {
      await prefs.setBool('front_camera_enabled', frontCamera);
      updates['frontCamera'] = frontCamera;
    }
    if (rearCamera != null) {
      await prefs.setBool('rear_camera_enabled', rearCamera);
      updates['rearCamera'] = rearCamera;
    }
    if (audioCapture != null) {
      await prefs.setBool('audio_capture_enabled', audioCapture);
      updates['audioCapture'] = audioCapture;
    }
    if (videoCapture != null) {
      await prefs.setBool('video_capture_enabled', videoCapture);
      updates['videoCapture'] = videoCapture;
    }
    if (photoCapture != null) {
      await prefs.setBool('photo_capture_enabled', photoCapture);
      updates['photoCapture'] = photoCapture;
    }

    // Update instance if it exists
    if (_instance._isInitialized) {
      _instance._settingsController.add(updates);
    }
  }

  // Initialize with default settings
  Future<void> _initializeDefaultSettings() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Set default values if not already set
    if (!prefs.containsKey(_emergencySoundKey)) {
      await prefs.setBool(_emergencySoundKey, true);
    }
    if (!prefs.containsKey(_alertSoundKey)) {
      await prefs.setBool(_alertSoundKey, true);
    }
    if (!prefs.containsKey(_vibrationKey)) {
      await prefs.setBool(_vibrationKey, true);
    }
    if (!prefs.containsKey('auto_upload_enabled')) {
      await prefs.setBool('auto_upload_enabled', true);
    }
    if (!prefs.containsKey('low_battery_mode_enabled')) {
      await prefs.setBool('low_battery_mode_enabled', false);
    }
    if (!prefs.containsKey('default_capture_strategy')) {
      await prefs.setString('default_capture_strategy', 'balanced');
    }
    if (!prefs.containsKey('front_camera_enabled')) {
      await prefs.setBool('front_camera_enabled', true);
    }
    if (!prefs.containsKey('rear_camera_enabled')) {
      await prefs.setBool('rear_camera_enabled', true);
    }
    if (!prefs.containsKey('audio_capture_enabled')) {
      await prefs.setBool('audio_capture_enabled', true);
    }
    if (!prefs.containsKey('video_capture_enabled')) {
      await prefs.setBool('video_capture_enabled', true);
    }
    if (!prefs.containsKey('photo_capture_enabled')) {
      await prefs.setBool('photo_capture_enabled', true);
    }
  }
}

// Add NetworkService class if it doesn't exist
class NetworkService {
  Future<void> initialize() async {
    // Implement network service initialization
  }

  Future<void> dispose() async {
    // Implement network service cleanup
  }
} 