import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:typed_data';
import 'dart:async';

late List<CameraDescription> _cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  if (await Permission.camera.request().isGranted) {
    _cameras = await availableCameras();
    runApp(FaceDetectionApp());
  } else {
    print("Camera permission denied");
  }
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
    _initializeCamera();
  }

  Future<void> _initializeCamera() async {
    if (_cameras.isEmpty) {
      print("No cameras found!");
      return;
    }

    // ✅ Open front camera by default
    _cameraIndex = _cameras.indexWhere((camera) => camera.lensDirection == CameraLensDirection.front);
    if (_cameraIndex == -1) _cameraIndex = 0; // If no front camera, fallback to first available

    _cameraController = CameraController(
      _cameras[_cameraIndex],
      ResolutionPreset.high, // High quality for better detection
      enableAudio: false,
    );

    try {
      await _cameraController!.initialize();

      // ✅ Ensure auto exposure & lighting
      await _cameraController!.setExposureMode(ExposureMode.auto);
      await _cameraController!.setFlashMode(FlashMode.auto);

      if (!mounted) return;
      setState(() {
        _isCameraInitialized = true;
      });
      _startFaceDetection();
    } catch (e) {
      print("Camera error: $e");
      setState(() {
        _isCameraInitialized = false;
      });
    }
  }

  void _switchCamera() async {
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    await _cameraController?.dispose();
    setState(() {
      _isCameraInitialized = false;
    });
    await _initializeCamera();
  }

  void _startFaceDetection() {
    if (_cameraController == null || !_cameraController!.value.isInitialized) {
      return;
    }

    _cameraController!.startImageStream((CameraImage image) async {
      if (_isDetecting) return;
      _isDetecting = true;

      try {
        final InputImage inputImage = _convertCameraImage(image);
        final List<Face> faces = await _faceDetector.processImage(inputImage);

        setState(() {
          _mood = faces.isNotEmpty ? _analyzeMood(faces.first) : "No face detected";
        });
      } catch (e) {
        print("Face detection error: $e");
      } finally {
        _isDetecting = false;
      }
    });
  }

  InputImage _convertCameraImage(CameraImage image) {
    final Uint8List bytes = convertYUV420ToNV21(image);
    final int rotation = _cameras[_cameraIndex].sensorOrientation;
    final InputImageMetadata metadata = InputImageMetadata(
      size: Size(image.width.toDouble(), image.height.toDouble()),
      rotation: _mapRotation(rotation),
      format: InputImageFormat.nv21,
      bytesPerRow: image.planes[0].bytesPerRow,
    );
    return InputImage.fromBytes(bytes: bytes, metadata: metadata);
  }

  Uint8List convertYUV420ToNV21(CameraImage image) {
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

    if (face.headEulerAngleY != null) {
      double tilt = face.headEulerAngleY!;
      if (tilt > 20) return "Looking Right ➡️";
      if (tilt < -20) return "Looking Left ⬅️";
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
              child: Container(
                padding: EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: Colors.black54,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _mood,
                  style: TextStyle(color: Colors.white, fontSize: 24),
                ),
              ),
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
