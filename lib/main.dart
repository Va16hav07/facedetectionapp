import 'dart:async';
import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_mlkit_face_detection/google_mlkit_face_detection.dart';
import 'package:tflite_flutter/tflite_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final cameras = await availableCameras();
  runApp(MyApp(cameras: cameras));
}

class MyApp extends StatelessWidget {
  final List<CameraDescription> cameras;
  const MyApp({super.key, required this.cameras});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: FaceDetectionScreen(cameras: cameras),
    );
  }
}

class FaceDetectionScreen extends StatefulWidget {
  final List<CameraDescription> cameras;
  const FaceDetectionScreen({super.key, required this.cameras});

  @override
  State<FaceDetectionScreen> createState() => _FaceDetectionScreenState();
}

class _FaceDetectionScreenState extends State<FaceDetectionScreen> {
  late CameraController _cameraController;
  bool isDetecting = false;
  final FaceDetector _faceDetector = FaceDetector(
    options: FaceDetectorOptions(enableClassification: true),
  );
  Interpreter? _interpreter;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _loadModel();
  }

  void _initializeCamera() {
    _cameraController = CameraController(widget.cameras[0], ResolutionPreset.medium);
    _cameraController.initialize().then((_) {
      if (!mounted) return;
      setState(() {});
      _startFaceDetection();
    });
  }

  Future<void> _loadModel() async {
    try {
      _interpreter = await Interpreter.fromAsset('emotion_model.tflite');
    } catch (e) {
      debugPrint("Failed to load model: $e");
    }
  }

  void _startFaceDetection() {
    _cameraController.startImageStream((CameraImage image) async {
      if (isDetecting) return;
      isDetecting = true;

      final inputImage = _convertCameraImage(image);
      final faces = await _faceDetector.processImage(inputImage);

      if (faces.isNotEmpty) {
        Face face = faces.first;
        String emotion = _analyzeFace(face);
        debugPrint("Detected Emotion: $emotion");
      }

      isDetecting = false;
    });
  }

  InputImage _convertCameraImage(CameraImage image) {
    final bytes = image.planes.map((plane) => plane.bytes).toList();
    return InputImage.fromBytes(
      bytes: Uint8List.fromList(bytes.expand((x) => x).toList()),
      metadata: InputImageMetadata(
        size: Size(image.width.toDouble(), image.height.toDouble()),
        rotation: InputImageRotation.rotation0deg,
        format: InputImageFormat.nv21,
        bytesPerRow: image.planes[0].bytesPerRow,
      ),
    );
  }

  String _analyzeFace(Face face) {
    if (face.smilingProbability != null && face.smilingProbability! > 0.7) {
      return "Happy 😊";
    } else if (face.leftEyeOpenProbability != null &&
        face.rightEyeOpenProbability != null &&
        face.leftEyeOpenProbability! < 0.3 &&
        face.rightEyeOpenProbability! < 0.3) {
      return "Tired 😴";
    } else {
      return "Neutral 😐";
    }
  }

  @override
  void dispose() {
    _cameraController.dispose();
    _faceDetector.close();
    _interpreter?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_cameraController.value.isInitialized) {
      return const Center(child: CircularProgressIndicator());
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Face Condition Detector')),
      body: Stack(
        children: [
          CameraPreview(_cameraController),
          Positioned(
            bottom: 20,
            left: 20,
            child: Container(
              padding: const EdgeInsets.all(10),
              color: Colors.black54,
              child: const Text(
                "Analyzing...",
                style: TextStyle(color: Colors.white, fontSize: 18),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
