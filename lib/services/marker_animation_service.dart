import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

/// Service to handle smooth marker animation between positions
class MarkerAnimationService {
  // Animation controllers
  final _positionController = StreamController<Position>.broadcast();
  final _headingController = StreamController<double>.broadcast();
  final _animationController = StreamController<AnimationState>.broadcast();
  
  // Animation state
  Timer? _animationTimer;
  Position? _startPosition;
  Position? _targetPosition;
  double? _startHeading;
  double? _targetHeading;
  DateTime? _animationStartTime;
  bool _isAnimating = false;
  List<Position> _positionBuffer = [];
  static const int _maxBufferSize = 5;

  // Animation settings
  static const Duration _animationDuration = Duration(milliseconds: 300); // Reduced for more responsive updates
  static const int _interpolationSteps = 20; // Increased for smoother animation
  static const double _minMovementDistance = 0.5; // meters
  static const double _minHeadingChange = 2.0; // degrees
  static const double _maxSpeed = 55.56; // 200 km/h
  static const double _accelerationFactor = 0.3; // For smooth acceleration/deceleration

  // Streams
  Stream<Position> get positionStream => _positionController.stream;
  Stream<double> get headingStream => _headingController.stream;
  Stream<AnimationState> get animationStream => _animationController.stream;

  /// Start animation between two positions with improved interpolation
  void animateToPosition(Position newPosition, {double? heading}) {
    if (_isAnimating) {
      _animationTimer?.cancel();
    }

    // Add position to buffer
    _positionBuffer.add(newPosition);
    if (_positionBuffer.length > _maxBufferSize) {
      _positionBuffer.removeAt(0);
    }

    if (_startPosition == null) {
      _startPosition = newPosition;
      _startHeading = heading;
      _positionController.add(newPosition);
      if (heading != null) {
        _headingController.add(heading);
      }
      return;
    }

    final distance = Geolocator.distanceBetween(
      _startPosition!.latitude,
      _startPosition!.longitude,
      newPosition.latitude,
      newPosition.longitude,
    );

    final headingChange = heading != null && _startHeading != null
        ? (heading - _startHeading!).abs()
        : 0.0;

    // Only animate if movement is significant
    if (distance > _minMovementDistance || headingChange > _minHeadingChange) {
      _targetPosition = newPosition;
      _targetHeading = heading;
      _startAnimation();
    } else {
      // For small movements, update immediately
      _startPosition = newPosition;
      _startHeading = heading;
      _positionController.add(newPosition);
      if (heading != null) {
        _headingController.add(heading);
      }
    }
  }

  void _startAnimation() {
    if (_startPosition == null || _targetPosition == null) return;

    _isAnimating = true;
    _animationStartTime = DateTime.now();
    int currentStep = 0;

    _animationTimer?.cancel();
    _animationTimer = Timer.periodic(
      Duration(milliseconds: _animationDuration.inMilliseconds ~/ _interpolationSteps),
      (timer) {
        if (currentStep >= _interpolationSteps) {
          _finishAnimation();
          return;
        }

        final progress = _calculateProgress(currentStep / _interpolationSteps);
        final interpolatedPosition = _interpolatePosition(
          _startPosition!,
          _targetPosition!,
          progress,
        );

        final interpolatedHeading = _interpolateHeading(
          _startHeading,
          _targetHeading,
          progress,
        );

        _positionController.add(interpolatedPosition);
        if (interpolatedHeading != null) {
          _headingController.add(interpolatedHeading);
        }

        _animationController.add(AnimationState(
          isAnimating: true,
          progress: progress,
          currentPosition: interpolatedPosition,
          currentHeading: interpolatedHeading,
        ));

        currentStep++;
      },
    );
  }

  double _calculateProgress(double rawProgress) {
    // Apply easing function for smooth acceleration/deceleration
    if (rawProgress < 0.5) {
      return 2 * rawProgress * rawProgress;
    } else {
      return -1 + (4 - 2 * rawProgress) * rawProgress;
    }
  }

  Position _interpolatePosition(Position start, Position end, double progress) {
    // Calculate speed-based interpolation
    final speed = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    ) / _animationDuration.inSeconds;

    // Apply acceleration/deceleration based on speed
    final adjustedProgress = speed > _maxSpeed
        ? progress * _accelerationFactor
        : progress;

    return Position(
      latitude: start.latitude + (end.latitude - start.latitude) * adjustedProgress,
      longitude: start.longitude + (end.longitude - start.longitude) * adjustedProgress,
      timestamp: DateTime.now(),
      accuracy: start.accuracy + (end.accuracy - start.accuracy) * progress,
      altitude: start.altitude + (end.altitude - start.altitude) * progress,
      speed: start.speed + (end.speed - start.speed) * progress,
      speedAccuracy: start.speedAccuracy + (end.speedAccuracy - start.speedAccuracy) * progress,
      heading: start.heading + (end.heading - start.heading) * progress,
      headingAccuracy: start.headingAccuracy + (end.headingAccuracy - start.headingAccuracy) * progress,
      altitudeAccuracy: start.altitudeAccuracy + (end.altitudeAccuracy - start.altitudeAccuracy) * progress,
    );
  }

  double? _interpolateHeading(double? start, double? end, double progress) {
    if (start == null || end == null) return null;

    // Handle heading wrap-around
    double diff = end - start;
    if (diff > 180) diff -= 360;
    if (diff < -180) diff += 360;

    return start + diff * progress;
  }

  void _finishAnimation() {
    _animationTimer?.cancel();
    _isAnimating = false;
    _startPosition = _targetPosition;
    _startHeading = _targetHeading;
    _targetPosition = null;
    _targetHeading = null;
    _animationStartTime = null;

    _animationController.add(AnimationState(
      isAnimating: false,
      progress: 1.0,
      currentPosition: _startPosition!,
      currentHeading: _startHeading,
    ));
  }

  void dispose() {
    _animationTimer?.cancel();
    _positionController.close();
    _headingController.close();
    _animationController.close();
  }
}

/// Represents the current state of marker animation
class AnimationState {
  final bool isAnimating;
  final double progress;
  final Position currentPosition;
  final double? currentHeading;

  AnimationState({
    required this.isAnimating,
    required this.progress,
    required this.currentPosition,
    this.currentHeading,
  });
} 