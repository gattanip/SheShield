import 'package:just_audio/just_audio.dart';
import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class EmergencyAudioService {
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  bool _isEmergencyActive = false;

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
    if (_isEmergencyActive) {
      debugPrint("Emergency audio is already active");
      return;
    }

    try {
      debugPrint("Starting emergency audio...");
      if (_audioPlayer == null) {
        debugPrint("Audio player not initialized, reinitializing...");
        await initialize();
      }

      _isEmergencyActive = true;
      await _audioPlayer?.seek(Duration.zero);
      await _audioPlayer?.play();
      
      final state = _audioPlayer?.playerState;
      debugPrint("Playback state after start: ${state?.processingState}");
      debugPrint("Playing status after start: ${state?.playing}");
      debugPrint("Emergency audio started successfully");
    } catch (e, stackTrace) {
      debugPrint("Error starting emergency audio: $e");
      debugPrint("Stack trace: $stackTrace");
      _isPlaying = false;
      _isEmergencyActive = false;
      
      try {
        await _audioPlayer?.stop();
        await initialize();
        _isEmergencyActive = true;
        await _audioPlayer?.play();
        debugPrint("Recovered from error and audio started");
      } catch (recoveryError) {
        debugPrint("Failed to recover audio error: $recoveryError");
        rethrow;
      }
    }
  }

  Future<void> stopEmergencySound() async {
    if (!_isEmergencyActive) {
      debugPrint("Emergency audio is not active");
      return;
    }

    try {
      debugPrint("Stopping emergency audio...");
      _isEmergencyActive = false;
      await _audioPlayer?.stop();
      _isPlaying = false;
      debugPrint("Emergency audio stopped successfully");
    } catch (e, stackTrace) {
      debugPrint("Error stopping emergency audio: $e");
      debugPrint("Stack trace: $stackTrace");
      _isPlaying = false;
      _isEmergencyActive = false;
      _audioPlayer?.stop();
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