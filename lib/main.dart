import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:google_mlkit_commons/google_mlkit_commons.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:async';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';

// Emotion data model
class EmotionData {
  final String mood;
  final double confidence;
  final DateTime timestamp;
  final String condition;
  final String lightingStatus;

  EmotionData({
    required this.mood,
    required this.confidence,
    required this.timestamp,
    required this.condition,
    required this.lightingStatus,
  });

  Map<String, dynamic> toJson() => {
        'mood': mood,
        'confidence': confidence,
        'timestamp': timestamp.toIso8601String(),
        'condition': condition,
        'lightingStatus': lightingStatus,
      };

  factory EmotionData.fromJson(Map<String, dynamic> json) => EmotionData(
        mood: json['mood'],
        confidence: json['confidence'],
        timestamp: DateTime.parse(json['timestamp']),
        condition: json['condition'],
        lightingStatus: json['lightingStatus'],
      );
}

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _cameras = await availableCameras();
  runApp(FaceDetectionApp());
}

class FaceDetectionApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primarySwatch: Colors.blue,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: Colors.black,
        cardTheme: CardTheme(
          color: Colors.black54,
          elevation: 8,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
        ),
        floatingActionButtonTheme: FloatingActionButtonThemeData(
          backgroundColor: Colors.black54,
          elevation: 8,
        ),
      ),
      home: FaceDetectionScreen(),
    );
  }
}

class FaceDetectionScreen extends StatefulWidget {
  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen>
    with SingleTickerProviderStateMixin {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(
      enableClassification: true,
      enableLandmarks: true,
      performanceMode: FaceDetectorMode.accurate,
    ),
  );

  bool _isDetecting = false;
  String _mood = "Analyzing...";
  String _lightingStatus = "";
  String _faceCondition = "";
  double _confidence = 0.0;
  int _cameraIndex = 0;
  bool _isCameraInitialized = false;
  Color _moodColor = Colors.white;
  Color _lightingColor = Colors.white;
  Color _conditionColor = Colors.white;
  bool _isLowLight = false;
  double _lastProcessedTime = 0;
  static const double _processingInterval = 0.1;
  AnimationController? _animationController;
  Animation<double>? _fadeAnimation;
  Animation<double>? _slideAnimation;
  List<EmotionData> _emotionHistory = [];
  static const String _historyKey = 'emotion_history';
  bool _showHistory = false;
  bool _isAnimationsInitialized = false;

  @override
  void initState() {
    super.initState();
    _initializeAnimations();
    _requestCameraPermission();
    _loadEmotionHistory();
  }

  void _initializeAnimations() {
    _animationController = AnimationController(
      duration: Duration(milliseconds: 500),
      vsync: this,
    );
    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeIn),
    );
    _slideAnimation = Tween<double>(begin: 50.0, end: 0.0).animate(
      CurvedAnimation(parent: _animationController!, curve: Curves.easeOut),
    );
    _isAnimationsInitialized = true;
  }

  /// **Request Camera Permission at Runtime**
  Future<void> _requestCameraPermission() async {
    var status = await Permission.camera.request();
    if (status.isGranted) {
      print("✅ Camera permission granted");
      _initializeCamera();
    } else {
      print("❌ Camera permission denied");
      setState(() => _mood = "Camera Permission Denied");
    }
  }

  /// **Initialize Camera**
  Future<void> _initializeCamera() async {
    if (_cameras.isEmpty) {
      print("❌ No cameras found!");
      return;
    }

    print("📷 Initializing camera at index: $_cameraIndex");

    try {
      _cameraController = CameraController(
        _cameras[_cameraIndex],
        ResolutionPreset.high,
        enableAudio: false,
      );

      await _cameraController!.initialize();

      if (!mounted) return;

      setState(() => _isCameraInitialized = true);
      print("✅ Camera initialized successfully.");
      _startFaceDetection();

      // Start animation only if it's initialized
      if (_isAnimationsInitialized && _animationController != null) {
        _animationController!.forward();
      }
    } catch (e) {
      print("❌ Camera initialization error: $e");
      setState(() => _isCameraInitialized = false);
    }
  }

  /// **Switch Between Front & Back Cameras**
  void _switchCamera() async {
    if (_cameras.length < 2) {
      print("⚠️ Only one camera found, cannot switch.");
      return;
    }

    print("🔄 Switching camera...");

    if (_cameraController != null &&
        _cameraController!.value.isStreamingImages) {
      print("⏹ Stopping image stream...");
      await _cameraController!.stopImageStream();
      await Future.delayed(Duration(milliseconds: 300));
    }

    print("🛑 Disposing current camera...");
    await _cameraController?.dispose();
    _cameraController = null;

    setState(() => _isCameraInitialized = false);

    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    print("📸 New camera index: $_cameraIndex");

    await Future.delayed(Duration(milliseconds: 500));

    print("🎥 Initializing new camera...");
    await _initializeCamera();
  }

  /// **Start Face Detection**
  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized)
      return;

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;

      final currentTime = DateTime.now().millisecondsSinceEpoch / 1000;
      if (currentTime - _lastProcessedTime < _processingInterval) return;
      _lastProcessedTime = currentTime;

      _isDetecting = true;

      try {
        final lightingStatus = _analyzeLighting(image);

        final InputImage inputImage = _convertCameraImage(image);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (!mounted) return;

        setState(() {
          _lightingStatus = lightingStatus['status']!;
          _lightingColor = lightingStatus['color']!;
          _isLowLight = lightingStatus['isLowLight']!;

          if (faces.isNotEmpty) {
            final face = faces.first;
            final moodResult = _analyzeMood(face);
            final conditionResult =
                _analyzeFaceCondition(face, lightingStatus['brightness']!);

            _mood = moodResult['mood']!;
            _confidence = moodResult['confidence']!;
            _moodColor = moodResult['color']!;
            _faceCondition = conditionResult['condition']!;
            _conditionColor = conditionResult['color']!;

            _addEmotionData();
          } else {
            _mood = "No face detected";
            _confidence = 0.0;
            _moodColor = Colors.white;
            _faceCondition = "";
            _conditionColor = Colors.white;
          }
        });
      } catch (e) {
        print("❌ Face detection error: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  /// **Convert Camera Image to InputImage**
  InputImage _convertCameraImage(CameraImage image) {
    // Convert YUV to NV21 format
    final bytes = _convertYUV420ToNV21(image);
    final rotation = _cameras[_cameraIndex].sensorOrientation;

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _mapRotation(rotation),
      format: InputImageFormat.nv21, // Changed format to nv21
      bytesPerRow: image.width, // Use image width for bytesPerRow
    );

    return InputImage.fromBytes(
      bytes: bytes,
      metadata: metadata,
    );
  }

  /// **Convert YUV_420 Image Format to NV21**
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);

    // Copy Y plane as-is
    nv21.setRange(0, ySize, image.planes[0].bytes);

    // Get U and V planes
    final Uint8List u = image.planes[1].bytes;
    final Uint8List v = image.planes[2].bytes;

    // Interleave V and U planes into NV21 format
    for (int i = 0, uvIndex = ySize; i < u.length; i++) {
      if (uvIndex < nv21.length - 1) {
        nv21[uvIndex++] = v[i];
        nv21[uvIndex++] = u[i];
      }
    }

    return nv21;
  }

  /// **Map Rotation for Face Detection**
  InputImageRotation _mapRotation(int rotation) {
    // Handle device orientation
    switch (rotation) {
      case 0:
        return InputImageRotation.rotation0deg;
      case 90:
        return InputImageRotation.rotation90deg;
      case 180:
        return InputImageRotation.rotation180deg;
      case 270:
        return InputImageRotation.rotation270deg;
      default:
        return InputImageRotation.rotation0deg;
    }
  }

  /// **Analyze Mood Based on Face Detection**
  Map<String, dynamic> _analyzeMood(Face face) {
    double? smileProb = face.smilingProbability;
    double? leftEyeOpen = face.leftEyeOpenProbability;
    double? rightEyeOpen = face.rightEyeOpenProbability;
    double? headEulerAngleY = face.headEulerAngleY;
    double? headEulerAngleZ = face.headEulerAngleZ;

    if (smileProb == null) {
      return {
        'mood': "Analyzing...",
        'confidence': 0.0,
        'color': Colors.white,
      };
    }

    // Calculate confidence based on multiple factors
    double confidence = 0.0;
    String mood = "Neutral 😐";
    Color color = Colors.white;

    // Analyze stress and tiredness
    if (leftEyeOpen != null && rightEyeOpen != null) {
      double eyeOpenness = (leftEyeOpen + rightEyeOpen) / 2;

      if (eyeOpenness < 0.3) {
        mood = "Tired 😴";
        color = Colors.purple;
        confidence = 1 - eyeOpenness;
      } else if (eyeOpenness < 0.5 && smileProb < 0.3) {
        mood = "Stressed 😫";
        color = Colors.red;
        confidence = 0.8;
      }
    }

    // Analyze happiness and sadness
    if (smileProb > 0.8) {
      mood = "Very Happy 😄";
      color = Colors.green;
      confidence = smileProb;
    } else if (smileProb > 0.5) {
      mood = "Happy 🙂";
      color = Colors.lightGreen;
      confidence = smileProb;
    } else if (smileProb < 0.2) {
      mood = "Sad 😢";
      color = Colors.blue;
      confidence = 1 - smileProb;
    }

    // Analyze head position
    if (headEulerAngleY != null && headEulerAngleZ != null) {
      if (headEulerAngleY.abs() > 20 || headEulerAngleZ.abs() > 20) {
        mood = "Looking Away 👀";
        color = Colors.yellow;
        confidence = 0.8;
      }
    }

    // Adjust confidence based on lighting conditions
    if (_isLowLight) {
      confidence *= 0.8; // Reduce confidence in low light
    }

    return {
      'mood': mood,
      'confidence': confidence,
      'color': color,
    };
  }

  Map<String, dynamic> _analyzeLighting(CameraImage image) {
    final Uint8List yPlane = image.planes[0].bytes;
    int totalBrightness = 0;
    int totalContrast = 0;
    int previousPixel = 0;

    // Sample every 10th pixel for performance
    for (int i = 0; i < yPlane.length; i += 10) {
      int currentPixel = yPlane[i];
      totalBrightness += currentPixel;
      totalContrast += (currentPixel - previousPixel).abs();
      previousPixel = currentPixel;
    }

    double averageBrightness = totalBrightness / (yPlane.length ~/ 10);
    double averageContrast = totalContrast / (yPlane.length ~/ 10);
    double normalizedBrightness = averageBrightness / 255.0;
    double normalizedContrast = averageContrast / 255.0;

    String status;
    Color color;
    bool isLowLight;

    if (normalizedBrightness < 0.3) {
      status = "Low Light ⚠️";
      color = Colors.orange;
      isLowLight = true;
    } else if (normalizedBrightness > 0.8) {
      status = "Too Bright ⚠️";
      color = Colors.yellow;
      isLowLight = false;
    } else {
      status = "Good Lighting ✅";
      color = Colors.green;
      isLowLight = false;
    }

    return {
      'status': status,
      'color': color,
      'isLowLight': isLowLight,
      'brightness': normalizedBrightness,
      'contrast': normalizedContrast,
    };
  }

  Map<String, dynamic> _analyzeFaceCondition(Face face, double brightness) {
    double? leftEyeOpen = face.leftEyeOpenProbability;
    double? rightEyeOpen = face.rightEyeOpenProbability;
    double? headEulerAngleY = face.headEulerAngleY;
    double? headEulerAngleZ = face.headEulerAngleZ;

    String condition = "Normal";
    Color color = Colors.green;
    double confidence = 1.0;

    if (leftEyeOpen != null && rightEyeOpen != null) {
      double eyeOpenness = (leftEyeOpen + rightEyeOpen) / 2;

      if (eyeOpenness < 0.3) {
        condition = "Fatigued";
        color = Colors.orange;
        confidence = 1 - eyeOpenness;
      } else if (eyeOpenness < 0.5) {
        condition = "Tired";
        color = Colors.yellow;
        confidence = 0.8;
      }
    }

    if (headEulerAngleY != null && headEulerAngleZ != null) {
      if (headEulerAngleY.abs() > 20 || headEulerAngleZ.abs() > 20) {
        condition = "Distracted";
        color = Colors.red;
        confidence = 0.9;
      }
    }

    // Adjust for lighting conditions
    if (brightness < 0.3) {
      condition += " (Low Light)";
      confidence *= 0.8;
    } else if (brightness > 0.8) {
      condition += " (Bright Light)";
      confidence *= 0.9;
    }

    return {
      'condition': condition,
      'color': color,
      'confidence': confidence,
    };
  }

  Future<void> _loadEmotionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String? historyJson = prefs.getString(_historyKey);
    if (historyJson != null) {
      final List<dynamic> historyList = json.decode(historyJson);
      setState(() {
        _emotionHistory =
            historyList.map((json) => EmotionData.fromJson(json)).toList();
      });
    }
  }

  Future<void> _saveEmotionHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final String historyJson =
        json.encode(_emotionHistory.map((data) => data.toJson()).toList());
    await prefs.setString(_historyKey, historyJson);
  }

  void _addEmotionData() {
    if (_mood != "Analyzing..." && _mood != "No face detected") {
      setState(() {
        _emotionHistory.add(EmotionData(
          mood: _mood,
          confidence: _confidence,
          timestamp: DateTime.now(),
          condition: _faceCondition,
          lightingStatus: _lightingStatus,
        ));
        // Keep only last 100 entries
        if (_emotionHistory.length > 100) {
          _emotionHistory.removeAt(0);
        }
      });
      _saveEmotionHistory();
    }
  }

  @override
  void dispose() {
    if (_isAnimationsInitialized && _animationController != null) {
      _animationController!.dispose();
    }
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Face Analysis"),
        backgroundColor: Colors.black87,
        elevation: 0,
        actions: [
          IconButton(
            icon: Icon(_showHistory ? Icons.camera_alt : Icons.history),
            onPressed: () {
              setState(() {
                _showHistory = !_showHistory;
              });
            },
          ),
          IconButton(
            icon: Icon(Icons.info_outline),
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: Colors.black87,
                  title: Text("About Face Analysis"),
                  content: Text(
                      "This app analyzes your facial expressions and conditions in real-time.\n\n"
                      "Features:\n"
                      "• Emotion Detection\n"
                      "• Fatigue Analysis\n"
                      "• Lighting Adaptation\n"
                      "• Real-time Feedback\n"
                      "• Emotion History"),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: Text("Close"),
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
      body: _showHistory
          ? _buildHistoryView()
          : _isCameraInitialized
              ? Stack(
                  children: [
                    Positioned.fill(child: CameraPreview(_cameraController!)),
                    // Overlay gradient for better text visibility
                    Positioned.fill(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.transparent,
                              Colors.black.withOpacity(0.7),
                            ],
                          ),
                        ),
                      ),
                    ),
                    // Analysis Card
                    if (_isAnimationsInitialized &&
                        _animationController != null &&
                        _fadeAnimation != null &&
                        _slideAnimation != null)
                      AnimatedBuilder(
                        animation: _animationController!,
                        builder: (context, child) {
                          return Positioned(
                            bottom: 80 + _slideAnimation!.value,
                            left: 20,
                            right: 20,
                            child: Opacity(
                              opacity: _fadeAnimation!.value,
                              child: Card(
                                child: Padding(
                                  padding: EdgeInsets.all(16),
                                  child: Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      // Lighting Status
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color:
                                              _lightingColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.lightbulb_outline,
                                                color: _lightingColor),
                                            SizedBox(width: 8),
                                            Text(
                                              _lightingStatus,
                                              style: TextStyle(
                                                fontSize: 18,
                                                fontWeight: FontWeight.bold,
                                                color: _lightingColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 12),
                                      // Face Condition
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color:
                                              _conditionColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.face,
                                                color: _conditionColor),
                                            SizedBox(width: 8),
                                            Text(
                                              _faceCondition,
                                              style: TextStyle(
                                                fontSize: 20,
                                                fontWeight: FontWeight.bold,
                                                color: _conditionColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 12),
                                      // Mood
                                      Container(
                                        padding: EdgeInsets.symmetric(
                                            horizontal: 12, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: _moodColor.withOpacity(0.2),
                                          borderRadius:
                                              BorderRadius.circular(20),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(Icons.psychology,
                                                color: _moodColor),
                                            SizedBox(width: 8),
                                            Text(
                                              _mood,
                                              style: TextStyle(
                                                fontSize: 24,
                                                fontWeight: FontWeight.bold,
                                                color: _moodColor,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      SizedBox(height: 12),
                                      // Confidence Bar
                                      Column(
                                        children: [
                                          ClipRRect(
                                            borderRadius:
                                                BorderRadius.circular(10),
                                            child: LinearProgressIndicator(
                                              value: _confidence,
                                              backgroundColor: Colors.white24,
                                              valueColor:
                                                  AlwaysStoppedAnimation<Color>(
                                                      _moodColor),
                                              minHeight: 8,
                                            ),
                                          ),
                                          SizedBox(height: 4),
                                          Text(
                                            "Confidence: ${(_confidence * 100).toStringAsFixed(1)}%",
                                            style: TextStyle(
                                              fontSize: 14,
                                              color: Colors.white70,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          );
                        },
                      ),
                    // Camera Switch Button
                    Positioned(
                      bottom: 20,
                      right: 20,
                      child: FloatingActionButton(
                        onPressed: _switchCamera,
                        child: Icon(Icons.switch_camera),
                        backgroundColor: Colors.black54,
                      ),
                    ),
                  ],
                )
              : Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                      SizedBox(height: 20),
                      Text(
                        "Initializing Camera...",
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  Widget _buildHistoryView() {
    if (_emotionHistory.isEmpty) {
      return Center(
        child: Text(
          "No emotion history yet",
          style: TextStyle(color: Colors.white70),
        ),
      );
    }

    return ListView.builder(
      itemCount: _emotionHistory.length,
      itemBuilder: (context, index) {
        final data = _emotionHistory[_emotionHistory.length - 1 - index];
        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: ListTile(
            leading: Icon(
              _getMoodIcon(data.mood),
              color: _getMoodColor(data.mood),
            ),
            title: Text(data.mood),
            subtitle: Text(
              "${data.condition}\n${data.lightingStatus}\n${data.timestamp.toString().substring(0, 16)}",
            ),
            trailing: CircularProgressIndicator(
              value: data.confidence,
              backgroundColor: Colors.white24,
              valueColor:
                  AlwaysStoppedAnimation<Color>(_getMoodColor(data.mood)),
            ),
          ),
        );
      },
    );
  }

  IconData _getMoodIcon(String mood) {
    if (mood.contains("Happy")) return Icons.sentiment_very_satisfied;
    if (mood.contains("Sad")) return Icons.sentiment_very_dissatisfied;
    if (mood.contains("Tired")) return Icons.sentiment_dissatisfied;
    if (mood.contains("Stressed")) return Icons.mood_bad;
    return Icons.sentiment_neutral;
  }

  Color _getMoodColor(String mood) {
    if (mood.contains("Happy")) return Colors.green;
    if (mood.contains("Sad")) return Colors.blue;
    if (mood.contains("Tired")) return Colors.purple;
    if (mood.contains("Stressed")) return Colors.red;
    return Colors.white;
  }
}
