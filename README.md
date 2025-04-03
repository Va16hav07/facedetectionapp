# Face Analysis App

A Flutter application that performs real-time face analysis using ML Kit Face Detection. The app detects emotions, lighting conditions, and face positioning to provide comprehensive facial analysis.

## Preview
<div align="center">
  <img src="https://github.com/user-attachments/assets/6ec00094-faa0-40a0-bc5f-932d6f3fab11" width="200" alt="App Screenshot 1">
  <img src="https://github.com/user-attachments/assets/c9fce828-c1a8-4860-94ed-a9ad6b3a94d8" width="200" alt="App Screenshot 2">
  <img src="https://github.com/user-attachments/assets/6313636d-5d74-487d-9d1e-3d74fe4f0079" width="200" alt="App Screenshot 3">
  <img src="https://github.com/user-attachments/assets/83a58747-0120-4e32-a805-0036a92e0a79" width="200" alt="App Screenshot 4">
</div>

## Features

- 🎭 **Real-time Emotion Detection**
  - Happy, Sad, Tired, Stressed, and Neutral states
  - Confidence scoring for each emotion

- 👁️ **Face Condition Analysis**
  - Fatigue detection
  - Distraction monitoring
  - Eye openness tracking

- 💡 **Lighting Analysis**
  - Real-time lighting quality assessment
  - Low-light warnings
  - Overexposure detection

- 📊 **History Tracking**
  - Emotion history storage
  - Timestamp-based tracking
  - Environmental conditions logging

- 🎛️ **Advanced Controls**
  - Camera switching
  - Grid overlay
  - Flash control

## Requirements

- Flutter SDK (2.0.0 or higher)
- Dart SDK (2.12.0 or higher)
- Android SDK (API 21 or higher)
- iOS 9.0 or higher

## Dependencies

```yaml
dependencies:
  flutter:
    sdk: flutter
  camera: ^0.10.0
  google_mlkit_face_detection: ^0.5.0
  google_mlkit_commons: ^0.3.0
  permission_handler: ^10.0.0
  shared_preferences: ^2.0.0
```

## Installation

1. Clone the repository:
```bash
git clone https://github.com/yourusername/facedetectionapp.git
```

2. Install dependencies:
```bash
flutter pub get
```

3. Run the app:
```bash
flutter run
```

## Usage

1. Launch the app and grant camera permissions
2. Position your face within the guide overlay
3. The app will automatically begin analyzing:
   - Emotional state
   - Lighting conditions
   - Face positioning
4. View real-time analysis results
5. Access history by tapping the history icon

## Permissions

The app requires the following permissions:
- Camera access for face detection
- Storage access for saving emotion history

## Contributing

1. Fork the repository
2. Create your feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add some amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## Acknowledgments

- Google ML Kit for Face Detection
- Flutter Camera plugin
- Flutter community for valuable packages

## Support

For support, please open an issue in the repository or contact the maintainers.

## Privacy Notice

This application processes all face detection locally on the device. No facial data is transmitted or stored externally.
