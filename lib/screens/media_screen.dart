import 'dart:io';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path/path.dart' as path;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:share_plus/share_plus.dart';

class MediaScreen extends StatefulWidget {
  const MediaScreen({super.key});

  @override
  State<MediaScreen> createState() => _MediaScreenState();
}

class _MediaScreenState extends State<MediaScreen> {
  List<Directory> _sosSessions = [];
  bool _isLoading = true;
  String? _error;
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  String? _currentPlayingFile;

  @override
  void initState() {
    super.initState();
    _loadSosSessions();
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Future<void> _loadSosSessions() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      // Request storage permission
      if (Platform.isAndroid) {
        final androidInfo = await DeviceInfoPlugin().androidInfo;
        if (androidInfo.version.sdkInt >= 33) {
          // Android 13+
          final permissions = [
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
          final status = await Permission.storage.status;
          if (!status.isGranted) {
            final result = await Permission.storage.request();
            if (!result.isGranted) {
              throw Exception('Storage permission denied');
            }
          }
        }
      }

      final baseDir = await getApplicationDocumentsDirectory();
      if (baseDir == null) {
        throw Exception('Application documents directory not available');
      }

      final sosDir = Directory('${baseDir.path}/SheShield');
      if (!await sosDir.exists()) {
        await sosDir.create(recursive: true);
      }

      // Get all SOS session directories
      final List<Directory> sessions = [];
      await for (final entity in sosDir.list()) {
        if (entity is Directory && entity.path.contains('SOS_')) {
          sessions.add(entity);
          }
        }

      // Sort sessions by date (newest first)
      sessions.sort((a, b) => b.path.compareTo(a.path));

      setState(() {
        _sosSessions = sessions;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _deleteSession(Directory session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Session?'),
        content: Text('Are you sure you want to delete this SOS session and all its contents?\n\n${path.basename(session.path)}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await session.delete(recursive: true);
        await _loadSosSessions();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Session deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting session: $e')),
          );
        }
      }
    }
  }

  Future<void> _viewSession(Directory session) async {
    final List<FileSystemEntity> files = [];
    await for (final entity in session.list()) {
      if (entity is File) {
        final path = entity.path.toLowerCase();
        if (path.endsWith('.jpg') || path.endsWith('.mp4') || path.endsWith('.m4a')) {
          try {
            final stat = await entity.stat();
            if (stat.size > 0) {
              files.add(entity);
            }
          } catch (e) {
            print('Error accessing file ${entity.path}: $e');
          }
        }
      }
    }

    // Sort files by name (which includes timestamp)
    files.sort((a, b) => a.path.compareTo(b.path));

    if (!mounted) return;

    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SessionViewScreen(
          session: session,
          files: files,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_error != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('SOS Captures'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadSosSessions,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.red),
              const SizedBox(height: 16),
              Text(_error!, style: const TextStyle(color: Colors.red)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _loadSosSessions,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (_sosSessions.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: const Text('SOS Captures'),
          actions: [
            IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: _loadSosSessions,
            ),
          ],
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 48, color: Colors.grey),
              const SizedBox(height: 16),
              const Text(
                'No SOS captures found',
                style: TextStyle(fontSize: 18, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Captured media will appear here',
                style: TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: _loadSosSessions,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('SOS Captures'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _loadSosSessions,
          ),
        ],
      ),
      body: ListView.builder(
        itemCount: _sosSessions.length,
        itemBuilder: (context, index) {
          final session = _sosSessions[index];
          final sessionName = path.basename(session.path);
          final timestamp = sessionName.split('_');
          final date = timestamp[0];
          final time = timestamp[1].replaceAll('-', ':');

          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: ListTile(
              leading: const Icon(Icons.folder, size: 40),
              title: Text('SOS Capture'),
              subtitle: Text('$date at $time'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.delete),
                    onPressed: () => _deleteSession(session),
                    color: Colors.red,
                  ),
                  IconButton(
                    icon: const Icon(Icons.folder_open),
                    onPressed: () => _viewSession(session),
                  ),
                ],
              ),
              onTap: () => _viewSession(session),
            ),
          );
        },
      ),
    );
  }
}

class SessionViewScreen extends StatefulWidget {
  final Directory session;
  final List<FileSystemEntity> files;

  const SessionViewScreen({
    super.key,
    required this.session,
    required this.files,
  });

  @override
  State<SessionViewScreen> createState() => _SessionViewScreenState();
}

class _SessionViewScreenState extends State<SessionViewScreen> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  String? _currentPlayingFile;

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  String _getFileType(String path) {
    if (path.endsWith('.jpg')) return 'Photo';
    if (path.endsWith('.mp4')) return 'Video';
    if (path.endsWith('.m4a')) return 'Audio';
    return 'Unknown';
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  Future<void> _playVideo(String path) async {
    if (_currentPlayingFile == path) {
      if (_videoController?.value.isPlaying ?? false) {
        await _videoController?.pause();
      } else {
        await _videoController?.play();
      }
      return;
    }

    await _videoController?.dispose();
    await _audioPlayer?.stop();

    final controller = VideoPlayerController.file(File(path));
    await controller.initialize();
    await controller.play();

    setState(() {
      _videoController = controller;
      _currentPlayingFile = path;
    });
  }

  Future<void> _playAudio(String path) async {
    if (_currentPlayingFile == path) {
      if (_audioPlayer?.playing ?? false) {
        await _audioPlayer?.pause();
      } else {
        await _audioPlayer?.play();
      }
      return;
    }

    await _videoController?.pause();
    await _audioPlayer?.stop();

    final player = AudioPlayer();
    await player.setFilePath(path);
    await player.play();

    setState(() {
      _audioPlayer = player;
      _currentPlayingFile = path;
    });
  }

  Future<void> _deleteFile(FileSystemEntity file) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete File?'),
        content: Text('Are you sure you want to delete this ${_getFileType(file.path).toLowerCase()}?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      try {
        await file.delete();
        setState(() {
          widget.files.remove(file);
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('File deleted successfully')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error deleting file: $e')),
          );
        }
      }
    }
  }

  Future<void> _shareFile(FileSystemEntity file) async {
    try {
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error sharing file: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Session: ${path.basename(widget.session.path)}'),
      ),
      body: GridView.builder(
        padding: const EdgeInsets.all(8),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
        ),
        itemCount: widget.files.length,
        itemBuilder: (context, index) {
          final file = widget.files[index];
          final path = file.path.toLowerCase();
          final fileType = _getFileType(path);
          final fileSize = _formatFileSize(file.statSync().size);
          final modified = DateFormat('MMM d, y HH:mm').format(file.statSync().modified);

          return Card(
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: () => _showMediaPreview(file),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        _buildMediaPreview(file),
                        if (path == _currentPlayingFile)
                          Container(
                            color: Colors.black54,
                            child: Center(
                              child: Icon(
                                path.endsWith('.mp4')
                                    ? (_videoController?.value.isPlaying ?? false)
                                        ? Icons.pause
                                        : Icons.play_arrow
                                    : (_audioPlayer?.playing ?? false)
                                        ? Icons.pause
                                        : Icons.play_arrow,
                                color: Colors.white,
                                size: 48,
                              ),
                            ),
                          ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              IconButton(
                                icon: const Icon(Icons.share, color: Colors.white),
                                onPressed: () => _shareFile(file),
                              ),
                              IconButton(
                                icon: const Icon(Icons.delete, color: Colors.white),
                                onPressed: () => _deleteFile(file),
                              ),
                            ],
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          fileType,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          fileSize,
                          style: const TextStyle(fontSize: 10),
                        ),
                        Text(
                          modified,
                          style: const TextStyle(fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMediaPreview(FileSystemEntity file) {
    final path = file.path.toLowerCase();
    if (path.endsWith('.jpg')) {
      return Image.file(
        File(file.path),
        fit: BoxFit.cover,
        errorBuilder: (context, error, stackTrace) {
          return const Icon(Icons.broken_image, size: 50);
        },
      );
    } else if (path.endsWith('.mp4')) {
      return FutureBuilder<VideoPlayerController>(
        future: () async {
          final controller = VideoPlayerController.file(File(file.path));
          await controller.initialize();
          return controller;
        }(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
            return AspectRatio(
              aspectRatio: snapshot.data!.value.aspectRatio,
              child: VideoPlayer(snapshot.data!),
            );
          }
          return const Center(child: CircularProgressIndicator());
        },
      );
    } else if (path.endsWith('.m4a')) {
      return const Icon(Icons.audio_file, size: 50);
    }
    return const Icon(Icons.file_present, size: 50);
  }

  void _showMediaPreview(FileSystemEntity file) {
    final path = file.path.toLowerCase();
    if (path.endsWith('.jpg')) {
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Image.file(File(file.path)),
        ),
      );
    } else if (path.endsWith('.mp4')) {
      VideoPlayerController? videoController;
      
      showDialog(
        context: context,
        builder: (context) => Dialog(
          child: Stack(
            children: [
              FutureBuilder<VideoPlayerController>(
                future: () async {
                  videoController = VideoPlayerController.file(File(file.path));
                  await videoController!.initialize();
                  await videoController!.play();
                  return videoController!;
                }(),
                builder: (context, snapshot) {
                  if (snapshot.connectionState == ConnectionState.done && snapshot.hasData) {
                    return AspectRatio(
                      aspectRatio: snapshot.data!.value.aspectRatio,
                      child: VideoPlayer(snapshot.data!),
                    );
                  }
                  return const Center(child: CircularProgressIndicator());
                },
              ),
              Positioned(
                top: 8,
                right: 8,
                child: IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  onPressed: () {
                    videoController?.pause();
                    videoController?.dispose();
                    Navigator.of(context).pop();
                  },
                ),
              ),
            ],
          ),
        ),
      ).then((_) {
        // Ensure controller is disposed when dialog is closed
        videoController?.pause();
        videoController?.dispose();
      });
    } else if (path.endsWith('.m4a')) {
      _playAudio(file.path);
    }
  }
} 