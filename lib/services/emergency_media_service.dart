import 'dart:async';
import 'dart:io';
import 'package:camera/camera.dart';
import 'package:googleapis/drive/v3.dart' as drive;
import 'package:googleapis_auth/auth_io.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:record/record.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:share_plus/share_plus.dart';
import 'package:synchronized/synchronized.dart';
import 'logging_service.dart';

/// Service to handle emergency media capture and upload
class EmergencyMediaService {
  static final EmergencyMediaService _instance = EmergencyMediaService._internal();
  factory EmergencyMediaService() => _instance;
  EmergencyMediaService._internal();

  static const String _driveLinkKey = 'emergency_drive_link';
  static const String _credentialsKey = 'drive_credentials';
  static const String _tokenKey = 'drive_token';
  static const List<String> _scopes = [
    'https://www.googleapis.com/auth/drive.file',
  ];
  
  // Default durations
  Duration _videoRecordingDuration = const Duration(minutes: 1);
  Duration _videoPauseDuration = const Duration(minutes: 2);
  Duration _audioRecordingDuration = const Duration(minutes: 5);
  Duration _audioPauseDuration = const Duration(minutes: 1);
  Duration _photoInterval = const Duration(minutes: 2);
  
  // State
  bool _isActive = false;
  String? _currentSessionId;
  Timer? _videoTimer;
  Timer? _audioTimer;
  Timer? _photoTimer;
  CameraController? _frontCamera;
  CameraController? _rearCamera;
  AudioPlayer? _audioPlayer;
  drive.DriveApi? _driveApi;
  final _uuid = Uuid();
  
  // Stream controllers
  final _uploadProgressController = StreamController<double>.broadcast();
  final _recordingStatusController = StreamController<bool>.broadcast();
  
  // Getters
  Stream<double> get uploadProgressStream => _uploadProgressController.stream;
  Stream<bool> get recordingStatusStream => _recordingStatusController.stream;
  bool get isActive => _isActive;
  
  String? _currentAudioPath;
  
  CameraController? _cameraController;
  final _audioRecorder = AudioRecorder();
  bool _isInitialized = false;
  bool _isCapturing = false;
  bool _isRecording = false;
  String _selectedCaptureStrategy = 'balanced';
  Timer? _captureTimer;
  int _captureInterval = 30; // seconds
  int _maxDuration = 300; // 5 minutes
  int _elapsedSeconds = 0;
  
  bool get isInitialized => _isInitialized;
  bool get isCapturing => _isCapturing;
  CameraController? get cameraController => _cameraController;
  
  // Add new fields for media tracking
  final Map<String, List<MediaFile>> _sessionMedia = {};
  final _mediaController = StreamController<List<MediaFile>>.broadcast();
  
  // Add getter for media stream
  Stream<List<MediaFile>> get mediaStream => _mediaController.stream;
  
  // Add new fields for upload queue
  final _uploadQueue = <MediaFile>[];
  bool _isUploading = false;
  
  final LoggingService _logger = LoggingService();
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseStorage _storage = FirebaseStorage.instance;
  
  Timer? _uploadTimer;
  
  String? get currentSessionId => _currentSessionId;
  
  Directory? _currentSessionDir;
  
  // Stream controllers
  final _captureStatusController = StreamController<CaptureStatus>.broadcast();
  
  // Getters
  Stream<CaptureStatus> get captureStatusStream => _captureStatusController.stream;
  Directory? get currentSessionDir => _currentSessionDir;
  
  // Add new state tracking variables
  bool _isPhotoCaptureInProgress = false;
  bool _isVideoRecordingInProgress = false;
  final _captureLock = Lock();
  
  /// Configure capture strategy
  Future<void> configureCaptureStrategy({
    required Duration videoDuration,
    required Duration videoPauseDuration,
    required Duration audioDuration,
    required Duration audioPauseDuration,
    required Duration photoInterval,
  }) async {
    if (_isActive) {
      throw Exception('Cannot configure strategy while capture is active');
    }

    _videoRecordingDuration = videoDuration;
    _videoPauseDuration = videoPauseDuration;
    _audioRecordingDuration = audioDuration;
    _audioPauseDuration = audioPauseDuration;
    _photoInterval = photoInterval;

    print('✅ [EmergencyMedia] Capture strategy configured:');
    print('  • Video: ${_videoRecordingDuration.inMinutes}m record, ${_videoPauseDuration.inMinutes}m pause');
    print('  • Audio: ${_audioRecordingDuration.inMinutes}m record, ${_audioPauseDuration.inMinutes}m pause');
    print('  • Photos: Every ${_photoInterval.inMinutes}m');
  }
  
  /// Initialize the service
  Future<void> initialize() async {
    if (_isInitialized) return;

    try {
      await _logger.initialize();
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Initializing media service...');
      
      // Request permissions
      await _checkAndRequestPermissions();

      // Initialize cameras with retry logic
      await _initializeCameras();

      _isInitialized = true;
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Media service initialized successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 'Failed to initialize media service', e, stackTrace);
      await _disposeCameras();
      rethrow;
    }
  }
  
  Future<void> _initializeCameras() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        throw Exception('No cameras available');
      }

      // Find front and rear cameras
      CameraDescription? frontCamera;
      CameraDescription? rearCamera;

      for (final camera in cameras) {
        if (camera.lensDirection == CameraLensDirection.front) {
          frontCamera = camera;
        } else if (camera.lensDirection == CameraLensDirection.back) {
          rearCamera = camera;
        }
      }

      // Initialize cameras with retry logic
      if (frontCamera != null) {
        _frontCamera = await _createCameraController(frontCamera, 'Front camera');
      }

      if (rearCamera != null) {
        _rearCamera = await _createCameraController(rearCamera, 'Rear camera');
      }

      // Set default camera controller
      _cameraController = _frontCamera ?? _rearCamera;

      if (_cameraController == null) {
        throw Exception('No camera controllers available');
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 'Error initializing cameras', e);
      await _disposeCameras();
      rethrow;
    }
  }

  Future<CameraController> _createCameraController(CameraDescription camera, String cameraName) async {
    final controller = CameraController(
      camera,
      ResolutionPreset.medium,
      enableAudio: true,
      imageFormatGroup: ImageFormatGroup.yuv420,
    );

    int retryCount = 0;
    const maxRetries = 3;
    bool initialized = false;

    while (!initialized && retryCount < maxRetries) {
      try {
        await controller.initialize().timeout(
          const Duration(seconds: 15),
          onTimeout: () => throw TimeoutException('$cameraName initialization timed out'),
        );

        if (controller.value.isInitialized) {
          // Only set focus mode and orientation, no flash
          await controller.setFocusMode(FocusMode.auto);
          await controller.lockCaptureOrientation();
          initialized = true;
          await _logger.log(LogLevel.info, 'EmergencyMediaService', '$cameraName initialized successfully');
        } else {
          throw Exception('$cameraName failed to initialize properly');
        }
      } catch (e) {
        retryCount++;
        await _logger.log(LogLevel.warning, 'EmergencyMediaService', 
          'Attempt $retryCount to initialize $cameraName failed: $e');
        
        if (retryCount >= maxRetries) {
          await controller.dispose();
          rethrow;
        }
        
        await Future.delayed(Duration(seconds: retryCount * 2));
      }
    }

    return controller;
  }

  Future<void> _disposeCameras() async {
    await _disposeCamera(_frontCamera);
    await _disposeCamera(_rearCamera);
    _frontCamera = null;
    _rearCamera = null;
    _cameraController = null;
  }

  Future<void> _disposeCamera(CameraController? controller) async {
    if (controller != null) {
      try {
        if (controller.value.isInitialized) {
          await controller.dispose();
        }
      } catch (e) {
        await _logger.log(LogLevel.warning, 'EmergencyMediaService', 
          'Error disposing camera: $e');
      }
    }
  }
  
  /// Set Google Drive folder link
  Future<void> setDriveFolderLink(String folderLink) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_driveLinkKey, folderLink);
      
      // Extract folder ID from link
      final folderId = _extractFolderId(folderLink);
      if (folderId == null) {
        throw Exception('Invalid Google Drive folder link');
      }
      
      // Initialize Drive API
      await _initializeDriveApi();
      
      print('✅ [EmergencyMedia] Drive folder link set');
    } catch (e) {
      print('❌ [EmergencyMedia] Error setting drive folder: $e');
      rethrow;
    }
  }
  
  /// Start emergency media capture
  Future<void> startMediaCapture() async {
    if (!_isInitialized) {
      throw Exception('Media service not initialized');
    }

    if (_isCapturing) {
      await _logger.log(LogLevel.warning, 'EmergencyMediaService', 'Media capture already active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Starting media capture...');
      
      // Reinitialize cameras if needed
      if (_cameraController == null || !_cameraController!.value.isInitialized) {
        await _initializeCameras();
      }
      
      // Create session directory
      final sessionDir = await _createSessionDirectory();
      _currentSessionDir = sessionDir;
      _currentSessionId = path.basename(sessionDir.path);
      
      // Start continuous capture sequence
      _captureTimer?.cancel();
      _isCapturing = true;
      
      // Start capture cycle immediately
      _executeCaptureSequence();
      
      // Then set up periodic capture
      _captureTimer = Timer.periodic(const Duration(seconds: 30), (_) {
        if (_isCapturing) {
          _executeCaptureSequence();
        }
      });

      _captureStatusController.add(CaptureStatus(
        isActive: true,
        currentStep: CaptureStep.starting,
        sessionId: _currentSessionId,
        sessionPath: sessionDir.path,
      ));
      
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Media capture started successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 'Error starting media capture', e, stackTrace);
      rethrow;
    }
  }
  
  /// Stop emergency media capture
  Future<void> stopMediaCapture() async {
    if (!_isCapturing) {
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Media capture not active');
      return;
    }

    try {
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Stopping media capture...');
      
      // Stop timers
      _captureTimer?.cancel();
      _captureTimer = null;
      
      // Stop any ongoing recordings
      await _stopVideoRecording();
      await _stopAudioRecording();
      
      _isCapturing = false;
      _currentSessionId = null;
      _currentSessionDir = null;
      
      _captureStatusController.add(CaptureStatus(
        isActive: false,
        currentStep: CaptureStep.stopped,
      ));
      
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Media capture stopped successfully');
    } catch (e, stackTrace) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 'Error stopping media capture', e, stackTrace);
      rethrow;
    }
  }
  
  Future<Directory> _createSessionDirectory() async {
    final timestamp = _getFormattedDateTime();
    final baseDir = await getApplicationDocumentsDirectory();
    if (baseDir == null) {
      throw Exception("Application documents directory not available");
    }
    
    // Create a folder under the app's documents directory
    final sosFolder = Directory("${baseDir.path}/SheShield/SOS_${timestamp}");
    if (!await sosFolder.exists()) {
      await sosFolder.create(recursive: true);
    }
    return sosFolder;
  }

  Future<void> _executeCaptureSequence() async {
    if (!_isInitialized || !_isCapturing) {
      return;
    }

    return _captureLock.synchronized(() async {
      try {
        if (!_isInitialized || _cameraController == null) {
          throw Exception('Camera not initialized');
        }

        final timestamp = DateTime.now().millisecondsSinceEpoch;
        final sessionDir = currentSessionDir;
        if (sessionDir == null) {
          throw Exception('Session directory not available');
        }

        // Update capture status
        _captureStatusController.add(CaptureStatus(
          isActive: true,
          currentStep: CaptureStep.capturingRearPhoto,
          sessionId: _currentSessionId,
          sessionPath: sessionDir.path,
        ));

        // Capture rear photo
        final rearPhotoPath = await _capturePhoto(
          sessionDir,
          'rear_photo_${timestamp}.jpg',
          isFrontCamera: false,
        );

        // Update status for front photo
        _captureStatusController.add(CaptureStatus(
          isActive: true,
          currentStep: CaptureStep.capturingFrontPhoto,
          sessionId: _currentSessionId,
          sessionPath: sessionDir.path,
        ));

        // Capture front photo
        final frontPhotoPath = await _capturePhoto(
          sessionDir,
          'front_photo_${timestamp}.jpg',
          isFrontCamera: true,
        );

        // Update status for video
        _captureStatusController.add(CaptureStatus(
          isActive: true,
          currentStep: CaptureStep.recordingRearVideo,
          sessionId: _currentSessionId,
          sessionPath: sessionDir.path,
        ));

        // Record video
        final videoPath = await _recordVideo(
          sessionDir,
          'rear_video_${timestamp}.mp4',
          isFrontCamera: false,
        );

        // Save media info
        await _saveMediaInfo(
          sessionDir.path,
          rearPhotoPath ?? 'failed',
          frontPhotoPath ?? 'failed',
          videoPath ?? 'failed',
        );

        // Log capture status
        await _logger.log(LogLevel.info, 'EmergencyMediaService', 
          'Capture sequence completed: ' +
          'Rear photo: ${rearPhotoPath != null}, ' +
          'Front photo: ${frontPhotoPath != null}, ' +
          'Video: ${videoPath != null}');

        // If capture is still active, prepare for next sequence
        if (_isCapturing) {
          _captureStatusController.add(CaptureStatus(
            isActive: true,
            currentStep: CaptureStep.starting,
            sessionId: _currentSessionId,
            sessionPath: sessionDir.path,
          ));
        }

      } catch (e, stackTrace) {
        await _logger.log(LogLevel.error, 'EmergencyMediaService', 
          'Error in capture sequence',
          e,
          stackTrace,
        );
        // Don't rethrow to allow continuous capture
        // If capture is still active, try again after a short delay
        if (_isCapturing) {
          await Future.delayed(const Duration(seconds: 5));
          _executeCaptureSequence();
        }
      }
    });
  }

  Future<String?> _capturePhoto(Directory sessionDir, String filename, {required bool isFrontCamera}) async {
    try {
      if (!_isInitialized || _cameraController == null) {
        throw Exception('Camera not initialized');
      }

      final file = File('${sessionDir.path}/$filename');
      final image = await _cameraController!.takePicture();
      if (image.path.isEmpty) {
        throw Exception('Failed to capture image');
      }

      await image.saveTo(file.path);
      await _logger.log(LogLevel.debug, 'EmergencyMediaService', 
        'Photo captured: ${file.path}');
      return file.path;
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 
        'Error capturing photo: $e');
      return null;
    }
  }

  Future<String?> _recordVideo(Directory sessionDir, String filename, {required bool isFrontCamera}) async {
    try {
      if (!_isInitialized || _cameraController == null || !_isCapturing) {
        return null;
      }

      final file = File('${sessionDir.path}/$filename');
      await _cameraController!.startVideoRecording();
      
      // Record for 10 seconds or until capture is stopped
      int recordingTime = 0;
      while (_isCapturing && recordingTime < 10) {
        await Future.delayed(const Duration(seconds: 1));
        recordingTime++;
      }
      
      if (!_isCapturing) {
        await _cameraController!.stopVideoRecording();
        return null;
      }
      
      final video = await _cameraController!.stopVideoRecording();
      if (video.path.isEmpty) {
        throw Exception('Failed to record video');
      }

      await video.saveTo(file.path);
      await _logger.log(LogLevel.debug, 'EmergencyMediaService', 
        'Video recorded: ${file.path}');
      return file.path;
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 
        'Error recording video: $e');
      return null;
    }
  }

  Future<void> _saveMediaInfo(String sessionPath, String rearPhotoPath, String frontPhotoPath, String videoPath) async {
    try {
      final mediaInfo = {
        'timestamp': DateTime.now().toIso8601String(),
        'session_path': sessionPath,
        'rear_photo': rearPhotoPath,
        'front_photo': frontPhotoPath,
        'video': videoPath,
      };

      final file = File('$sessionPath/media_info.json');
      await file.writeAsString(jsonEncode(mediaInfo));
      
      _logger.log(LogLevel.debug, 'EmergencyMediaService', 
        'Media info saved successfully',
        null,
        null,
      );
    } catch (e, stackTrace) {
      _logger.log(LogLevel.error, 'EmergencyMediaService', 
        'Error saving media info',
        e,
        stackTrace,
      );
      // Don't rethrow - this is not critical
    }
  }
  
  /// Start video capture cycle
  void _startVideoCaptureCycle() {
    _videoTimer?.cancel();
    _videoTimer = Timer.periodic(
      _videoRecordingDuration + _videoPauseDuration,
      (timer) async {
        if (!_isActive) {
          timer.cancel();
          return;
        }
        
        try {
          // Record video
          await _startVideoRecording();
          await Future.delayed(_videoRecordingDuration);
          await _stopVideoRecording();
          
          // Notify status
          _recordingStatusController.add(true);
        } catch (e) {
          print('❌ [EmergencyMedia] Error in video cycle: $e');
        }
      },
    );
  }
  
  /// Start audio capture cycle
  void _startAudioCaptureCycle() {
    _audioTimer?.cancel();
    _audioTimer = Timer.periodic(
      _audioRecordingDuration + _audioPauseDuration,
      (timer) async {
        if (!_isActive) {
          timer.cancel();
          return;
        }
        
        try {
          // Record audio
          await _startAudioRecording();
          await Future.delayed(_audioRecordingDuration);
          await _stopAudioRecording();
          
          // Notify status
          _recordingStatusController.add(true);
        } catch (e) {
          print('❌ [EmergencyMedia] Error in audio cycle: $e');
        }
      },
    );
  }
  
  /// Start video recording
  Future<void> _startVideoRecording() async {
    if (!_isCapturing || _cameraController == null) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${appDir.path}/emergency_media/sos_${_getFormattedDateTime()}');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = File('${sessionDir.path}/video_$timestamp.mp4');

      await _cameraController!.startVideoRecording();
      
      // Track the media file
      final mediaFile = MediaFile(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        path: file.path,
        type: MediaType.video,
        timestamp: DateTime.now(),
        uploaded: false,
        driveFileId: null,
      );
      
      _addMediaFile(mediaFile);
      
      _videoTimer = Timer(_videoRecordingDuration, () async {
        await _stopVideoRecording(mediaFile);
      });
      
      debugPrint('Video recording started: ${file.path}');
    } catch (e) {
      debugPrint('Error starting video recording: $e');
    }
  }
  
  /// Stop video recording
  Future<void> _stopVideoRecording([MediaFile? mediaFile]) async {
    if (_cameraController == null || !_cameraController!.value.isRecordingVideo) return;

    try {
      final file = await _cameraController!.stopVideoRecording();
      
      if (mediaFile != null) {
        mediaFile.path = file.path;
        _updateMediaFile(mediaFile);
        await _uploadFile(mediaFile);
      }
      
      debugPrint('Video recording stopped: ${file.path}');
    } catch (e) {
      debugPrint('Error stopping video recording: $e');
    }
  }
  
  /// Start audio recording
  Future<void> _startAudioRecording() async {
    if (!_isCapturing) return;

    try {
      final appDir = await getApplicationDocumentsDirectory();
      final sessionDir = Directory('${appDir.path}/emergency_media/sos_${_getFormattedDateTime()}');
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final file = '${sessionDir.path}/audio_$timestamp.m4a';

      await _audioRecorder.start(
        RecordConfig(
          encoder: AudioEncoder.aacLc,
          bitRate: 128000,
          sampleRate: 44100,
        ),
        path: file,
      );

      // Track the media file
      final mediaFile = MediaFile(
        id: const Uuid().v4(),
        sessionId: _currentSessionId!,
        path: file,
        type: MediaType.audio,
        timestamp: DateTime.now(),
        uploaded: false,
        driveFileId: null,
      );
      
      _addMediaFile(mediaFile);
      _currentAudioPath = file;

      _audioTimer = Timer(_audioRecordingDuration, () async {
        await _stopAudioRecording(mediaFile);
      });
      
      debugPrint('Audio recording started: $file');
    } catch (e) {
      debugPrint('Error starting audio recording: $e');
    }
  }
  
  /// Stop audio recording
  Future<void> _stopAudioRecording([MediaFile? mediaFile]) async {
    if (!_isCapturing) return;

    try {
      await _audioRecorder.stop();
      
      if (mediaFile != null && _currentAudioPath != null) {
        mediaFile.path = _currentAudioPath!;
        _updateMediaFile(mediaFile);
        await _uploadFile(mediaFile);
      }
      
      debugPrint('Audio recording stopped: ${_currentAudioPath}');
    } catch (e) {
      debugPrint('Error stopping audio recording: $e');
    }
  }
  
  /// Upload file to Google Drive
  Future<void> _uploadFile(MediaFile mediaFile) async {
    if (_driveApi == null) {
      debugPrint('Drive API not initialized, storing for later upload');
      await _storeFailedUpload(mediaFile.path, '${mediaFile.path.split('/').last}', MediaType.values.firstWhere((e) => e.toString() == mediaFile.type.toString()));
      return;
    }
    
    try {
      final file = File(mediaFile.path);
      if (!await file.exists()) {
        throw Exception('File not found: ${mediaFile.path}');
      }
      
      final fileSize = await file.length();
      var uploadedBytes = 0;
      
      debugPrint('Uploading file: ${mediaFile.path}');
      
      final media = drive.Media(
        file.openRead().transform(
          StreamTransformer<List<int>, List<int>>.fromHandlers(
            handleData: (data, sink) {
              uploadedBytes += data.length;
              sink.add(data);
              
              // Report progress
              _uploadProgressController.add(uploadedBytes / fileSize);
            },
          ),
        ),
        fileSize,
      );
      
      final driveFile = drive.File()
        ..name = mediaFile.path.split('/').last
        ..parents = [_extractFolderId(await _getDriveFolderLink())!]
        ..mimeType = _getMimeType(MediaType.values.firstWhere((e) => e.toString() == mediaFile.type.toString()));
      
      final result = await _driveApi!.files.create(
        driveFile,
        uploadMedia: media,
      );
      
      // Update media file with drive info
      mediaFile.uploaded = true;
      mediaFile.driveFileId = result.id;
      _updateMediaFile(mediaFile);
      
      debugPrint('File uploaded: ${result.name} (${result.id})');
    } catch (e) {
      debugPrint('Error uploading file: $e');
      await _storeFailedUpload(mediaFile.path, '${mediaFile.path.split('/').last}', MediaType.values.firstWhere((e) => e.toString() == mediaFile.type.toString()));
    }
  }
  
  /// Upload remaining files
  Future<void> _uploadRemainingFiles() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final failedUploads = prefs.getStringList('failed_uploads') ?? [];
      
      if (failedUploads.isEmpty) {
        print('ℹ️ [EmergencyMedia] No failed uploads to retry');
        return;
      }
      
      print('🔄 [EmergencyMedia] Retrying ${failedUploads.length} failed uploads...');
      
      for (final upload in failedUploads) {
        final data = upload.split('|');
        if (data.length == 3) {
          try {
            await _uploadFile(
              MediaFile(
                id: const Uuid().v4(),
                sessionId: _currentSessionId!,
                path: data[0],
                type: MediaType.values.firstWhere(
                  (type) => type.toString() == data[2],
                ),
                timestamp: DateTime.now(),
                uploaded: false,
                driveFileId: null,
              ),
            );
          } catch (e) {
            print('❌ [EmergencyMedia] Error retrying upload: $e');
            // Keep in failed uploads list
            continue;
          }
        }
      }
      
      // Clear failed uploads list
      await prefs.remove('failed_uploads');
      print('✅ [EmergencyMedia] Failed uploads retry completed');
    } catch (e) {
      print('❌ [EmergencyMedia] Error uploading remaining files: $e');
      rethrow;
    }
  }
  
  /// Store failed upload for retry
  Future<void> _storeFailedUpload(String filePath, String fileName, MediaType type) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final failedUploads = prefs.getStringList('failed_uploads') ?? [];
      failedUploads.add('$filePath|$fileName|$type');
      await prefs.setStringList('failed_uploads', failedUploads);
    } catch (e) {
      print('❌ [EmergencyMedia] Error storing failed upload: $e');
    }
  }
  
  /// Initialize Drive API
  Future<void> _initializeDriveApi() async {
    try {
      print('🔄 [EmergencyMedia] Initializing Drive API...');
      final prefs = await SharedPreferences.getInstance();
      final credentialsJson = prefs.getString(_credentialsKey);
      final tokenJson = prefs.getString(_tokenKey);
      if (credentialsJson == null) {
        throw Exception('Drive credentials not set');
      }
      // Parse credentials
      final serviceAccount = ServiceAccountCredentials.fromJson(
        json.decode(credentialsJson) as Map<String, dynamic>,
      );
      AccessCredentials? accessCredentials;
      if (tokenJson != null) {
        final token = AccessCredentials.fromJson(
          json.decode(tokenJson) as Map<String, dynamic>,
        );
        if (token.accessToken.expiry.isAfter(DateTime.now())) {
          accessCredentials = token;
        }
      }
      if (accessCredentials == null) {
        // Get new token
        accessCredentials = await obtainAccessCredentialsViaServiceAccount(
          serviceAccount,
          _scopes,
          http.Client(),
        );
        // Save token
        await prefs.setString(
          _tokenKey,
          json.encode(accessCredentials.toJson()),
        );
      }
      // Create authenticated client
      final client = authenticatedClient(
        http.Client(),
        accessCredentials,
      );
      // Initialize Drive API
      _driveApi = drive.DriveApi(client);
      print('✅ [EmergencyMedia] Drive API initialized');
    } catch (e) {
      print('❌ [EmergencyMedia] Error initializing Drive API: $e');
      rethrow;
    }
  }
  
  /// Set Google Drive credentials
  Future<void> setDriveCredentials(String credentialsJson) async {
    try {
      // Validate credentials format
      final credentials = ServiceAccountCredentials.fromJson(
        json.decode(credentialsJson) as Map<String, dynamic>,
      );
      
      // Save credentials
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_credentialsKey, credentialsJson);
      
      // Clear existing token
      await prefs.remove(_tokenKey);
      
      // Initialize Drive API
      await _initializeDriveApi();
      
      print('✅ [EmergencyMedia] Drive credentials set');
    } catch (e) {
      print('❌ [EmergencyMedia] Error setting drive credentials: $e');
      rethrow;
    }
  }
  
  /// Get MIME type for media type
  String _getMimeType(MediaType type) {
    switch (type) {
      case MediaType.image:
        return 'image/jpeg';
      case MediaType.video:
        return 'video/mp4';
      case MediaType.audio:
        return 'audio/m4a';
    }
  }
  
  /// Check and request permissions
  Future<void> _checkAndRequestPermissions() async {
    if (Platform.isAndroid) {
      final androidInfo = await DeviceInfoPlugin().androidInfo;
      if (androidInfo.version.sdkInt >= 33) {
        // Android 13+
        final permissions = [
          Permission.camera,
          Permission.microphone,
          Permission.photos,
          Permission.videos,
          Permission.audio,
        ];
        
        for (final permission in permissions) {
          final status = await permission.status;
          if (!status.isGranted) {
            final result = await permission.request();
            if (!result.isGranted) {
              throw Exception('${permission.toString()} permission denied');
            }
          }
        }
      } else {
        // Android < 13
    final permissions = [
      Permission.camera,
      Permission.microphone,
      Permission.storage,
    ];
        
    for (final permission in permissions) {
      final status = await permission.status;
      if (!status.isGranted) {
        final result = await permission.request();
        if (!result.isGranted) {
          throw Exception('${permission.toString()} permission denied');
            }
          }
        }
      }
    }
  }
  
  /// Get stored drive folder link
  Future<String> _getDriveFolderLink() async {
    final prefs = await SharedPreferences.getInstance();
    final link = prefs.getString(_driveLinkKey);
    if (link == null) {
      throw Exception('Drive folder link not set');
    }
    return link;
  }
  
  /// Extract folder ID from drive link
  String? _extractFolderId(String link) {
    // Handle different Google Drive link formats
    final uri = Uri.parse(link);
    if (uri.host.contains('drive.google.com')) {
      if (uri.pathSegments.contains('folders')) {
        return uri.pathSegments.last;
      } else if (uri.queryParameters.containsKey('id')) {
        return uri.queryParameters['id'];
      }
    }
    return null;
  }
  
  /// Dispose the service
  Future<void> dispose() async {
    try {
      await stopMediaCapture();
      // Ensure cameras are properly disposed
      await _disposeCameras();
      await _audioRecorder.dispose();
      await _audioPlayer?.dispose();
      _uploadProgressController.close();
      _recordingStatusController.close();
      _mediaController.close();
      _captureStatusController.close();
      debugPrint('EmergencyMediaService disposed');
    } catch (e) {
      debugPrint('Error disposing EmergencyMediaService: $e');
    }
  }

  void setCaptureStrategy(String strategy) {
    _selectedCaptureStrategy = strategy;
    switch (strategy) {
      case 'balanced':
        _captureInterval = 30;
        break;
      case 'aggressive':
        _captureInterval = 15;
        break;
      case 'conservative':
        _captureInterval = 60;
        break;
    }
  }

  String _getFormattedDateTime() {
    final now = DateTime.now();
    return '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}_${now.hour.toString().padLeft(2, '0')}-${now.minute.toString().padLeft(2, '0')}';
  }

  /// Add media file to tracking
  void _addMediaFile(MediaFile mediaFile) {
    if (_currentSessionId != null) {
      _sessionMedia[_currentSessionId]?.add(mediaFile);
      _notifyMediaUpdate();
    }
  }

  /// Update media file in tracking
  void _updateMediaFile(MediaFile mediaFile) {
    if (_currentSessionId != null) {
      final index = _sessionMedia[_currentSessionId]?.indexWhere((m) => m.id == mediaFile.id) ?? -1;
      if (index != -1) {
        _sessionMedia[_currentSessionId]?[index] = mediaFile;
        _notifyMediaUpdate();
      }
    }
  }

  /// Notify media update
  void _notifyMediaUpdate() {
    if (_currentSessionId != null) {
      _mediaController.add(_sessionMedia[_currentSessionId] ?? []);
    }
  }

  /// Get media files for a session
  List<MediaFile> getSessionMedia(String sessionId) {
    return _sessionMedia[sessionId] ?? [];
  }

  /// Get all media files
  List<MediaFile> getAllMedia() {
    return _sessionMedia.values.expand((list) => list).toList();
  }

  Future<void> _processUploadQueue() async {
    if (_isUploading || _uploadQueue.isEmpty) return;

    _isUploading = true;
    try {
      while (_uploadQueue.isNotEmpty) {
        final mediaFile = _uploadQueue.removeAt(0);
        if (!mediaFile.uploaded) {
          await _uploadFile(mediaFile);
        }
      }
    } finally {
      _isUploading = false;
      if (_uploadQueue.isNotEmpty) {
        _processUploadQueue(); // Process any new items added during upload
      }
    }
  }

  // Add new method for sharing media
  Future<void> shareMedia(String sessionId) async {
    try {
      final mediaFiles = getSessionMedia(sessionId);
      if (mediaFiles.isEmpty) {
        throw Exception('No media files found for session');
      }

      // Create a list of files to share
      final files = <XFile>[];
      for (final mediaFile in mediaFiles) {
        final file = File(mediaFile.path);
        if (await file.exists()) {
          files.add(XFile(file.path));
        }
      }

      if (files.isEmpty) {
        throw Exception('No valid files to share');
      }

      // Share files using platform sharing
      await Share.shareXFiles(
        files,
        text: 'Emergency Media from SheShield - Session: $sessionId',
      );
      
      await _logger.log(LogLevel.info, 'EmergencyMediaService', 'Media shared successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyMediaService', 'Error sharing media: $e');
      rethrow;
    }
  }
}

/// Media types
enum MediaType {
  image,
  video,
  audio,
}

/// Media file model
class MediaFile {
  final String id;
  final String sessionId;
  String path;
  final MediaType type;
  final DateTime timestamp;
  bool uploaded;
  String? driveFileId;

  MediaFile({
    required this.id,
    required this.sessionId,
    required this.path,
    required this.type,
    required this.timestamp,
    required this.uploaded,
    this.driveFileId,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'sessionId': sessionId,
    'path': path,
    'type': type.toString(),
    'timestamp': timestamp.toIso8601String(),
    'uploaded': uploaded,
    'driveFileId': driveFileId,
  };

  factory MediaFile.fromJson(Map<String, dynamic> json) => MediaFile(
    id: json['id'],
    sessionId: json['sessionId'],
    path: json['path'],
    type: MediaType.values.firstWhere(
      (e) => e.toString() == json['type'],
    ),
    timestamp: DateTime.parse(json['timestamp']),
    uploaded: json['uploaded'],
    driveFileId: json['driveFileId'],
  );
}

/// Capture status model
class CaptureStatus {
  final bool isActive;
  final CaptureStep currentStep;
  final String? sessionId;
  final String? sessionPath;

  CaptureStatus({
    required this.isActive,
    required this.currentStep,
    this.sessionId,
    this.sessionPath,
  });
}

/// Capture steps
enum CaptureStep {
  starting,
  capturingRearPhoto,
  capturingFrontPhoto,
  recordingRearVideo,
  recordingFrontVideo,
  stopped,
} 