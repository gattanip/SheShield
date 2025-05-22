import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:io';
import 'logging_service.dart';

class EmergencyAudioService {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  bool _isEmergencyActive = false;
  final LoggingService _logger = LoggingService();

  Future<void> initialize() async {
    try {
      debugPrint('Initializing emergency audio service...');
      
      // Create new audio player instance
      _audioPlayer = AudioPlayer();
      
      // Basic audio session configuration
      final session = await AudioSession.instance;
      await session.configure(const AudioSessionConfiguration(
        avAudioSessionCategory: AVAudioSessionCategory.playback,
        avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
        avAudioSessionMode: AVAudioSessionMode.defaultMode,
        androidAudioAttributes: AndroidAudioAttributes(
          contentType: AndroidAudioContentType.music,
          flags: AndroidAudioFlags.none,
          usage: AndroidAudioUsage.media,
        ),
      ));

      debugPrint('Audio session configured');

      // Set volume to maximum
      await _audioPlayer?.setVolume(1.0);
      debugPrint('Volume set to maximum');
      
      // Load the emergency audio file
      debugPrint('Loading audio file: assets/audio/help_me.wav');
      try {
        await _audioPlayer?.setAsset('assets/audio/help_me.wav');
        debugPrint('Audio file loaded successfully');
      } catch (e) {
        debugPrint('Failed to load audio file: $e');
        rethrow;
      }
      
      // Set to loop mode
      await _audioPlayer?.setLoopMode(LoopMode.all);
      debugPrint('Loop mode set to all');
      
      // Add error listener
      _audioPlayer?.playbackEventStream.listen(
        (event) {
          debugPrint('Playback event: $event');
        },
        onError: (Object e, StackTrace stackTrace) {
          debugPrint('Error in playback: $e');
          debugPrint('Stack trace: $stackTrace');
          _isPlaying = false;
          _isEmergencyActive = false;
        },
      );

      // Add player state listener
      _audioPlayer?.playerStateStream.listen((state) {
        debugPrint('Player state: ${state.processingState}');
        debugPrint('Playing: ${state.playing}');
        _isPlaying = state.playing;
        
        if (state.processingState == ProcessingState.completed) {
          debugPrint('Playback completed, restarting...');
          if (_isEmergencyActive) {
            _audioPlayer?.seek(Duration.zero);
            _audioPlayer?.play();
          }
        }
      });
      
      debugPrint('Emergency audio service initialized successfully');
    } catch (e, stackTrace) {
      debugPrint('Error initializing emergency audio: $e');
      debugPrint('Stack trace: $stackTrace');
      _isPlaying = false;
      _isEmergencyActive = false;
      rethrow;
    }
  }

  Future<void> startEmergencySound() async {
    if (_isPlaying) {
      await _logger.log(LogLevel.info, 'EmergencyAudioService', 'Emergency sound already playing');
      return;
    }

    try {
      // Request audio permissions first
      await _requestAudioPermissions();
      
      // Initialize audio player if needed
      if (_audioPlayer == null) {
        _audioPlayer = AudioPlayer();
        await _audioPlayer!.setAsset('assets/audio/help_me.mp3');
        await _audioPlayer!.setLoopMode(LoopMode.all);
        await _audioPlayer!.setVolume(1.0);
      }

      // Ensure audio session is active
      await _audioPlayer!.setAudioSource(
        AudioSource.asset('assets/audio/help_me.mp3'),
        preload: true,
      );

      // Start playback
      await _audioPlayer!.play();
      _isPlaying = true;
      
      // Listen for playback errors
      _audioPlayer!.playerStateStream.listen((state) {
        if (state.processingState == ProcessingState.completed) {
          // Restart if playback completes (shouldn't happen due to loop mode)
          _audioPlayer?.play();
        }
      }, onError: (e) async {
        await _logger.log(LogLevel.error, 'EmergencyAudioService', 'Audio playback error', e);
        // Try to recover
        await _recoverAudioPlayback();
      });

      await _logger.log(LogLevel.info, 'EmergencyAudioService', 'Emergency sound started successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyAudioService', 'Error starting emergency sound', e);
      // Try to recover
      await _recoverAudioPlayback();
      rethrow;
    }
  }

  Future<void> _requestAudioPermissions() async {
    try {
      final status = await Permission.audio.request();
      if (!status.isGranted) {
        throw Exception('Audio permission denied');
      }
      
      // Additional check for Android audio focus
      if (Platform.isAndroid) {
        final result = await const MethodChannel('com.SheShield.app/audio')
            .invokeMethod<bool>('requestAudioFocus');
        if (result != true) {
          throw Exception('Failed to get audio focus');
        }
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyAudioService', 'Error requesting audio permissions', e);
      rethrow;
    }
  }

  Future<void> _recoverAudioPlayback() async {
    try {
      // Dispose existing player
      await _audioPlayer?.dispose();
      _audioPlayer = null;
      
      // Wait a moment before retrying
      await Future.delayed(const Duration(milliseconds: 500));
      
      // Try to start playback again
      if (_isPlaying) {
        await startEmergencySound();
      }
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyAudioService', 'Error recovering audio playback', e);
    }
  }

  Future<void> stopEmergencySound() async {
    if (!_isPlaying) {
      await _logger.log(LogLevel.info, 'EmergencyAudioService', 'Emergency sound not playing');
      return;
    }

    try {
      await _audioPlayer?.stop();
      _isPlaying = false;
      
      // Release audio focus on Android
      if (Platform.isAndroid) {
        await const MethodChannel('com.SheShield.app/audio')
            .invokeMethod('abandonAudioFocus');
      }
      
      await _logger.log(LogLevel.info, 'EmergencyAudioService', 'Emergency sound stopped successfully');
    } catch (e) {
      await _logger.log(LogLevel.error, 'EmergencyAudioService', 'Error stopping emergency sound', e);
      rethrow;
    }
  }

  bool get isPlaying => _isPlaying;
  bool get isEmergencyActive => _isEmergencyActive;

  void dispose() {
    debugPrint('Disposing emergency audio service');
    _isPlaying = false;
    _isEmergencyActive = false;
    _audioPlayer?.dispose();
    _audioPlayer = null;
  }
} 