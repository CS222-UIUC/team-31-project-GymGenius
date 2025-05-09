import 'dart:io';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:video_player/video_player.dart';
import 'package:firebase_core/firebase_core.dart';

class RecordPage extends StatefulWidget {
  const RecordPage({super.key});

  @override
  State<RecordPage> createState() => _RecordPageState();
}

class _RecordPageState extends State<RecordPage> {
  CameraController? _cameraController;
  late Future<void> _initializeCameraFuture;
  bool _isRecording = false;
  bool _isPaused = false;
  bool _isCameraReady = false;
  bool _workoutSaved = false;
  Timer? _timer;
  int _secondsElapsed = 0;
  int _totalWorkoutSeconds = 0;
  VideoPlayerController? _videoController;
  DateTime? _workoutStartTime;
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  User? _currentUser;
  String _userEmail = '';

  @override
  void initState() {
    super.initState();
    _currentUser = _auth.currentUser;
    _userEmail = _currentUser?.email ?? 'Not logged in';
    //_initializeFirebaseAndCamera();
    _initializeFirebaseAndCamera().then((_) {
      //_writeTestData(); // Add this line
    });
    _resetWorkoutData();
  }

  Future<void> _writeTestData() async {
    try {
      final user = _auth.currentUser;
      if (user == null) {
        debugPrint('No user logged in - skipping test data');
        return;
      }

      final now = DateTime.now();
      final testData = {
        'date': FieldValue.serverTimestamp(),
        'duration': 300, // 5 minutes in seconds
        'startTime': Timestamp.fromDate(now.subtract(Duration(minutes: 5))),
        'endTime': Timestamp.fromDate(now),
        'userId': user.uid,
        'userEmail': user.email ?? 'no-email',
      };

      await _firestore
          .collection('userWorkouts')
          .doc(user.uid)
          .collection('workouts')
          .add(testData);

      debugPrint('Successfully wrote test workout data');
    } catch (e) {
      debugPrint('Error writing test data: $e');
    }
  }

  Future<void> _resetWorkoutData() async {
    setState(() {
      _secondsElapsed = 0;
      _totalWorkoutSeconds = 0;
      _isRecording = false;
      _isPaused = false;
      _workoutSaved = false;
    });
    _videoController?.dispose();
    _videoController = null;
  }

  Future<void> _initializeFirebaseAndCamera() async {
    try {
      await Firebase.initializeApp();

      final cameras = await availableCameras();
      final firstCamera = cameras.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _cameraController = CameraController(
        firstCamera,
        ResolutionPreset.medium,
        enableAudio: false,
      );

      _initializeCameraFuture = _cameraController!.initialize().then((_) {
        if (!mounted) return;
        setState(() => _isCameraReady = true);
      });
    } catch (e) {
      debugPrint('Initialization error: $e');
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Initialization failed: $e')));
      }
    }
  }

  Future<void> _startRecording() async {
    if (!_isCameraReady) return;

    await _resetWorkoutData();

    _workoutStartTime = DateTime.now();
    await _cameraController!.startVideoRecording();
    _startTimer();
    setState(() {
      _isRecording = true;
      _isPaused = false;
    });
  }

  Future<void> _pauseRecording() async {
    if (!_isRecording || _isPaused) return;

    await _cameraController!.pauseVideoRecording();
    _stopTimer();
    setState(() => _isPaused = true);
  }

  Future<void> _resumeRecording() async {
    if (!_isRecording || !_isPaused) return;

    await _cameraController!.resumeVideoRecording();
    _startTimer();
    setState(() => _isPaused = false);
  }

  Future<void> _endWorkout() async {
    if (!_isRecording) return;

    try {
      final file = await _cameraController!.stopVideoRecording();
      _stopTimer();

      if (mounted) {
        _previewVideo(file);
      }

      try {
        await _saveWorkoutData();
        if (mounted) {
          setState(() {
            _isRecording = false;
            _isPaused = false;
            _workoutSaved = true;
          });
        }

        Future.delayed(const Duration(seconds: 2), () {
          if (mounted) {
            setState(() => _workoutSaved = false);
          }
        });
      } catch (e) {
        debugPrint('Workout data save error: $e');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error saving workout data: $e'),
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    } catch (e) {
      debugPrint('Video recording stop error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error stopping recording: $e'),
            duration: const Duration(seconds: 4),
          ),
        );
      }
      setState(() {
        _isRecording = false;
        _isPaused = false;
      });
    }
  }

  Future<void> _saveWorkoutData() async {
    try {
      if (_currentUser == null) {
        throw Exception('User not authenticated');
      }

      if (_workoutStartTime == null) {
        throw Exception('Workout start time not set');
      }

      final workoutData = {
        'duration': _totalWorkoutSeconds,
        'date': FieldValue.serverTimestamp(),
        'startTime': Timestamp.fromDate(_workoutStartTime!),
        'endTime': Timestamp.now(),
        'userId': _currentUser!.uid,
        'userEmail': _currentUser!.email ?? 'no-email',
      };

      debugPrint('Saving workout data: $workoutData');

      await _firestore
          .collection('userWorkouts')
          .doc(_currentUser!.uid)
          .collection('workouts')
          .add(workoutData);

      debugPrint('Workout data saved successfully');
    } catch (e, stackTrace) {
      debugPrint('Firestore error: $e');
      debugPrint('Stack trace: $stackTrace');
      rethrow;
    }
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _secondsElapsed++;
        _totalWorkoutSeconds++;
      });
    });
  }

  void _stopTimer() {
    _timer?.cancel();
    _timer = null;
  }

  void _previewVideo(XFile file) {
    _videoController?.dispose();
    _videoController = VideoPlayerController.file(File(file.path))
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _videoController!.play();
      });
  }

  String _formatTime(int seconds) {
    final minutes = (seconds / 60).floor();
    final remainingSeconds = seconds % 60;
    return '$minutes:${remainingSeconds.toString().padLeft(2, '0')}';
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _videoController?.dispose();
    _timer?.cancel();
    super.dispose();
  }

  Widget _cameraPreview() {
    if (!_isCameraReady || _cameraController == null) {
      return const Center(child: CircularProgressIndicator());
    }
    
    // Get the screen size
    final size = MediaQuery.of(context).size;
    
    // Get the camera's aspect ratio
    final cameraAspectRatio = _cameraController!.value.aspectRatio;
    
    // Calculate the correct preview size
    return AspectRatio(
      aspectRatio: cameraAspectRatio,
      child: CameraPreview(_cameraController!),
    );
  }

  Widget _videoPreview() {
    if (_videoController == null || !_videoController!.value.isInitialized) {
      return Container();
    }
  
    return AspectRatio(
      aspectRatio: _videoController!.value.aspectRatio,
      child: VideoPlayer(_videoController!),
    );
  }

  Widget _buildControlButtons() {
    if (_workoutSaved) {
      return const Padding(
        padding: EdgeInsets.all(16.0),
        child: Text(
          'Workout Saved!',
          style: TextStyle(
            fontSize: 20,
            color: Colors.green,
            fontWeight: FontWeight.bold,
          ),
        ),
      );
    } else if (!_isRecording) {
      return FloatingActionButton(
        backgroundColor: Colors.green,
        onPressed: _startRecording,
        child: const Icon(Icons.videocam),
      );
    } else if (!_isPaused) {
      return FloatingActionButton(
        backgroundColor: Colors.orange,
        onPressed: _pauseRecording,
        child: const Icon(Icons.pause),
      );
    } else {
      return Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          FloatingActionButton(
            backgroundColor: Colors.blue,
            onPressed: _resumeRecording,
            child: const Icon(Icons.play_arrow),
          ),
          const SizedBox(width: 20),
          FloatingActionButton(
            backgroundColor: Colors.red,
            onPressed: _endWorkout,
            child: const Icon(Icons.stop),
          ),
        ],
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Record Workout'),

        //Only to display email top right
        // actions: [
        //   Padding(
        //     padding: const EdgeInsets.all(8.0),
        //     child: Column(
        //       mainAxisAlignment: MainAxisAlignment.center,
        //       crossAxisAlignment: CrossAxisAlignment.end,
        //       children: [
        //         Text(_userEmail, style: const TextStyle(fontSize: 12)),
        //       ],
        //     ),
        //   ),
        // ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: Text(
              _formatTime(_secondsElapsed),
              style: const TextStyle(fontSize: 32, fontWeight: FontWeight.bold),
            ),
          ),

          Expanded(
            child: Center(
              child: Container(
                constraints: BoxConstraints(
                  maxWidth: MediaQuery.of(context).size.width * 0.9,
                  maxHeight: MediaQuery.of(context).size.height * 0.6,
                ),
                child: _videoController != null && _videoController!.value.isInitialized
                    ? _videoPreview()
                    : _cameraPreview(),
              ),
            ),
          ),

          Padding(
            padding: const EdgeInsets.all(24.0),
            child: _buildControlButtons(),
          ),
        ],
      ),
    );
  }
}

