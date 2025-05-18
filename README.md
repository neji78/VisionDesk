# VisionPocket

**VisionPocket** is a Flutter-based mobile app that performs object detection using a remote YOLOv8 inference service. Users can select or capture images, send them to the backend API, and view detection results with labeled bounding boxes and confidence scores.

It pairs perfectly with [VisionGuard](https://github.com/neji78/object_detection_service), a FastAPI-based object detection backend using YOLOv8.

---

## 📱 Features

- 📷 Select images from gallery or camera
- 🌐 Send images to a remote object detection API
- 🎯 Display detected objects with class labels and confidence
- 🖼️ Annotated image with bounding boxes
- 🧪 Includes a backend test endpoint for development

---

## 🚀 Getting Started

### 1. Clone the Repository

```bash
git clone https://github.com/neji78/VisionDesk.git
cd VisionDesk
```

### 2. Install Dependencies

```
flutter pub get
```

### 3. Configure Backend API

Open lib/utils/constants.dart and set the API URL:
```
const String apiUrl = 'http://<YOUR_API_SERVER>/detect/';
```
Make sure your backend server (e.g., VisionGuard) is running and reachable from your device.

### 4. Run the App

```
flutter run
```
Make sure an Android/iOS emulator or physical device is connected.

### 📁 Project Structure

```
.
├── lib/
│   ├── main.dart               # Entry point
│   ├── screens/                # UI Screens
│   ├── widgets/                # Reusable UI components
│   ├── services/               # API call and response handling
│   └── utils/constants.dart    # API URL and static values
├── assets/                     # App icons and images
├── pubspec.yaml                # Dependencies
└── README.md

```
