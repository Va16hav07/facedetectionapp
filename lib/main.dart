import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:async';

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
      home: FaceDetectionScreen(),
    );
  }
}

class FaceDetectionScreen extends StatefulWidget {
  @override
  _FaceDetectionScreenState createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  CameraController? _cameraController;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(enableClassification: true, enableLandmarks: true),
  );

  bool _isDetecting = false;
  String _mood = "Analyzing...";
  int _cameraIndex = 0;
  bool _isCameraInitialized = false;

  @override
  void initState() {
    super.initState();
    _requestCameraPermission();
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

    if (_cameraController != null && _cameraController!.value.isStreamingImages) {
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
    if (_cameraController == null || !_cameraController!.value.isInitialized) return;

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;

      try {
        final InputImage inputImage = _convertCameraImage(image);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        if (!mounted) return;

        setState(() {
          _mood = faces.isNotEmpty ? _analyzeMood(faces.first) : "No face detected";
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
    final Uint8List bytes = _convertYUV420ToNV21(image);
    final int rotation = _cameras[_cameraIndex].sensorOrientation;

    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _mapRotation(rotation),
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes[0].bytesPerRow,
    );

    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  /// **Convert YUV_420 Image Format to NV21**
  Uint8List _convertYUV420ToNV21(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final int ySize = width * height;
    final int uvSize = ySize ~/ 2;
    final Uint8List nv21 = Uint8List(ySize + uvSize);

    nv21.setRange(0, ySize, image.planes[0].bytes);

    Uint8List u = image.planes[1].bytes;
    Uint8List v = image.planes[2].bytes;

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
    switch (rotation) {
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
  String _analyzeMood(Face face) {
    double? smileProb = face.smilingProbability;
    double? leftEyeOpen = face.leftEyeOpenProbability;
    double? rightEyeOpen = face.rightEyeOpenProbability;

    if (smileProb == null) return "Analyzing...";

    if (smileProb > 0.8) return "Very Happy 😄";
    if (smileProb > 0.5) return "Happy 🙂";
    if (smileProb > 0.2) return "Neutral 😐";
    if (smileProb < 0.2) return "Sad 😢";

    if (leftEyeOpen != null && rightEyeOpen != null) {
      if (leftEyeOpen < 0.3 && rightEyeOpen < 0.3) return "Sleepy 😴";
      if (leftEyeOpen > 0.7 && rightEyeOpen > 0.7) return "Surprised 😲";
    }

    return "Normal 🙂";
  }

  @override
  void dispose() {
    _cameraController?.dispose();
    _faceDetector.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Face Condition Detection")),
      body: _isCameraInitialized
          ? Stack(
        children: [
          Positioned.fill(child: CameraPreview(_cameraController!)),
          Positioned(
            bottom: 80,
            left: 20,
            right: 20,
            child: Center(
              child: Text(_mood, style: TextStyle(fontSize: 24, color: Colors.white)),
            ),
          ),
          Positioned(
            bottom: 20,
            right: 20,
            child: FloatingActionButton(
              onPressed: _switchCamera,
              child: Icon(Icons.switch_camera),
            ),
          ),
        ],
      )
          : Center(child: CircularProgressIndicator()),
    );
  }
}
