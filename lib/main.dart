// Copyright 2013 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// ignore_for_file: public_member_api_docs

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:image/image.dart' as img;
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:image_picker/image_picker.dart';
import 'package:logger/logger.dart';
import 'package:mime/mime.dart';
import 'package:video_player/video_player.dart';

import 'controller.dart';
import 'model.dart';

var logger = Logger(printer: PrettyPrinter());
List<CameraDescription>? cameras;

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  cameras = await availableCameras();
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Camera Preview Demo',
      home: CameraHomePage(title: 'Camera Preview'),
    );
  }
}

class CameraHomePage extends StatefulWidget {
  final String title;
  const CameraHomePage({super.key, required this.title});

  @override
  State<CameraHomePage> createState() => _CameraHomePageState();
}

class _CameraHomePageState extends State<CameraHomePage> {
  CameraController? _controller;
  CameraImage? _latestImage;
  bool _isDetecting = false;
  final yolo_controller = YoloDetectionController(serverUrl: 'http://172.16.15.39:5000');
  List<Map<String, dynamic>> _boxes = [];

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  Future<void> _initCamera() async {
    if (cameras == null || cameras!.isEmpty) return;
    _controller = CameraController(
      cameras![0],
      ResolutionPreset.medium,
      enableAudio: false,
    );
    await _controller!.initialize();
    if (!mounted) return;
    setState(() {});
    _controller!.startImageStream((CameraImage image) {
      _latestImage = image;
    });
  }

  Future<void> _onDetectPressed() async {
    if (_latestImage == null || _isDetecting) return;
    setState(() => _isDetecting = true);

    try {
      // Convert CameraImage to JPEG bytes
      Uint8List? jpegBytes = await _convertCameraImageToJpeg(_latestImage!);
      if (jpegBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to convert image.')),
        );
        setState(() => _isDetecting = false);
        return;
      }

      // Send to your detection API
      final List<DetectionResult>? detectedObjects =
          await yolo_controller.detectObjectsFromBytes(jpegBytes);

      logger.d('${detectedObjects?.length} Object Detected');
      _boxes.clear();

      // You may need to get the image size for normalization
      final decoded = img.decodeJpg(jpegBytes);
      double orginalWidth = decoded?.width.toDouble() ?? 1.0;
      double orginalHeight = decoded?.height.toDouble() ?? 1.0;

      for (var object in detectedObjects ?? []) {
        logger.d('Object is ${object.label} with confidence ${object.confidence} that box is ${object.bbox}');
        var x1 = object.bbox[0] / orginalWidth;
        var y1 = object.bbox[1] / orginalHeight;
        var width = (object.bbox[2] - object.bbox[0]) / orginalWidth;
        var height = (object.bbox[3] - object.bbox[1]) / orginalHeight;
        _boxes.add({
          "x1": x1,
          "y1": y1,
          "width": width,
          "height": height,
          "label": object.label,
          "confidence": object.confidence,
        });
      }

      setState(() {});
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Detected ${_boxes.length} objects.')),
      );
    } catch (e) {
      logger.e('Detection error: $e');
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Detection failed: $e')),
      );
    } finally {
      setState(() => _isDetecting = false);
    }
  }

  // Helper: Convert CameraImage to JPEG bytes
  Future<Uint8List?> _convertCameraImageToJpeg(CameraImage image) async {
    try {
      // Only works for YUV420 format (Android)
      if (image.format.group == ImageFormatGroup.yuv420) {
        final img.Image converted = _convertYUV420ToImage(image);
        final jpg = img.encodeJpg(converted);
        return Uint8List.fromList(jpg);
      }
      // For iOS, you may need to handle BGRA8888
      return null;
    } catch (e) {
      logger.e('Conversion error: $e');
      return null;
    }
  }

  // YUV420 to RGB conversion (Android)
  img.Image _convertYUV420ToImage(CameraImage image) {
    final int width = image.width;
    final int height = image.height;
    final img.Image imgImage = img.Image(width: width, height: height);

    final plane0 = image.planes[0].bytes;
    final plane1 = image.planes[1].bytes;
    final plane2 = image.planes[2].bytes;

    int uvRowStride = image.planes[1].bytesPerRow;
    int uvPixelStride = image.planes[1].bytesPerPixel!;

    for (int y = 0; y < height; y++) {
      for (int x = 0; x < width; x++) {
        final int uvIndex =
            uvPixelStride * (x ~/ 2) + uvRowStride * (y ~/ 2);
        final int index = y * width + x;

        final yp = plane0[index];
        final up = plane1[uvIndex];
        final vp = plane2[uvIndex];

        int r = (yp + vp * 1436 / 1024 - 179).clamp(0, 255).toInt();
        int g = (yp - up * 46549 / 131072 + 44 - vp * 93604 / 131072 + 91)
            .clamp(0, 255)
            .toInt();
        int b = (yp + up * 1814 / 1024 - 227).clamp(0, 255).toInt();

        imgImage.setPixelRgba(x, y, r, g, b);
      }
    }
    return imgImage;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: _controller == null || !_controller!.value.isInitialized
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                CameraPreview(_controller!),
                // Optionally draw boxes on top of preview
                ..._boxes.map((box) => Positioned(
                      left: box["x1"] * MediaQuery.of(context).size.width,
                      top: box["y1"] * MediaQuery.of(context).size.height,
                      width: box["width"] * MediaQuery.of(context).size.width,
                      height: box["height"] * MediaQuery.of(context).size.height,
                      child: Container(
                        decoration: BoxDecoration(
                          border: Border.all(color: Colors.red, width: 2),
                        ),
                        child: Align(
                          alignment: Alignment.topLeft,
                          child: Container(
                            color: Colors.red.withOpacity(0.5),
                            child: Text(
                              "${box["label"]} ${(box["confidence"] * 100).toStringAsFixed(1)}%",
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                      ),
                    )),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _onDetectPressed,
        label: const Text('Detect'),
        icon: const Icon(Icons.search),
      ),
    );
  }
}

// class MyHomePage extends StatefulWidget {
//   const MyHomePage({super.key, this.title});

//   final String? title;

//   @override
//   State<MyHomePage> createState() => _MyHomePageState();
// }
//
// class _MyHomePageState extends State<MyHomePage> {
//   List<XFile>? _mediaFileList;
//   final yolo_controller = YoloDetectionController(serverUrl: 'http://172.16.15.39:5000');
//   List<Map<String, dynamic>> _boxes = [];
//
//   void _setImageFileListFromFile(XFile? value) {
//     _mediaFileList = value == null ? null : <XFile>[value];
//   }
//
//   dynamic _pickImageError;
//   bool isVideo = false;
//
//   VideoPlayerController? _controller;
//   VideoPlayerController? _toBeDisposed;
//   String? _retrieveDataError;
//
//   final ImagePicker _picker = ImagePicker();
//   final TextEditingController maxWidthController = TextEditingController();
//   final TextEditingController maxHeightController = TextEditingController();
//   final TextEditingController qualityController = TextEditingController();
//   final TextEditingController limitController = TextEditingController();
//
//   Future<void> _playVideo(XFile? file) async {
//     if (file != null && mounted) {
//       await _disposeVideoController();
//       late VideoPlayerController controller;
//       if (kIsWeb) {
//         controller = VideoPlayerController.networkUrl(Uri.parse(file.path));
//       } else {
//         controller = VideoPlayerController.file(File(file.path));
//       }
//       _controller = controller;
//       // In web, most browsers won't honor a programmatic call to .play
//       // if the video has a sound track (and is not muted).
//       // Mute the video so it auto-plays in web!
//       // This is not needed if the call to .play is the result of user
//       // interaction (clicking on a "play" button, for example).
//       const double volume = kIsWeb ? 0.0 : 1.0;
//       await controller.setVolume(volume);
//       await controller.initialize();
//       await controller.setLooping(true);
//       await controller.play();
//       setState(() {});
//     }
//   }
//
//   Future<void> _onImageButtonPressed(
//       ImageSource source, {
//         required BuildContext context,
//         bool isMultiImage = false,
//         bool isMedia = false,
//       }) async {
//     if (_controller != null) {
//       await _controller!.setVolume(0.0);
//     }
//     if (context.mounted) {
//       if (isVideo) {
//         final XFile? file = await _picker.pickVideo(
//             source: source, maxDuration: const Duration(seconds: 10));
//         await _playVideo(file);
//       } else if (isMultiImage) {
//         await _displayPickImageDialog(context, true, (double? maxWidth,
//             double? maxHeight, int? quality, int? limit) async {
//           try {
//             final List<XFile> pickedFileList = isMedia
//                 ? await _picker.pickMultipleMedia(
//               maxWidth: maxWidth,
//               maxHeight: maxHeight,
//               imageQuality: quality,
//               limit: limit,
//             )
//                 : await _picker.pickMultiImage(
//               maxWidth: maxWidth,
//               maxHeight: maxHeight,
//               imageQuality: quality,
//               limit: limit,
//             );
//             setState(() {
//               _mediaFileList = pickedFileList;
//             });
//           } catch (e) {
//             setState(() {
//               _pickImageError = e;
//             });
//           }
//         });
//       } else if (isMedia) {
//         await _displayPickImageDialog(context, false, (double? maxWidth,
//             double? maxHeight, int? quality, int? limit) async {
//           try {
//             final List<XFile> pickedFileList = <XFile>[];
//             final XFile? media = await _picker.pickMedia(
//               maxWidth: maxWidth,
//               maxHeight: maxHeight,
//               imageQuality: quality,
//             );
//             if (media != null) {
//               pickedFileList.add(media);
//               setState(() {
//                 _mediaFileList = pickedFileList;
//               });
//             }
//           } catch (e) {
//             setState(() {
//               _pickImageError = e;
//             });
//           }
//         });
//       } else {
//         await _displayPickImageDialog(context, false, (double? maxWidth,
//             double? maxHeight, int? quality, int? limit) async {
//           try {
//             logger.d('image resource:'+ source.toString());
//             final XFile? pickedFile = await _picker.pickImage(
//               source: source,
//               maxWidth: maxWidth,
//               maxHeight: maxHeight,
//               imageQuality: quality,
//             );
//             double orginalWidth = 0.0;
//             double orginalHeight = 0.0;
//             if (pickedFile != null) {
//               File imageFile = File(pickedFile.path);
//               final bytes = await imageFile.readAsBytes();
//
//               final ui.Image image = await decodeImageFromList(bytes);
//               logger.d("imageSizes: Width: ${image.width}, Height: ${image.height}");
//               orginalWidth = image.width.toDouble();
//               orginalHeight = image.height.toDouble();
//             }
//             logger.d('image resource:${pickedFile?.path}');
//             final List<DetectionResult>? detectedObjects = await yolo_controller.detectObjects(pickedFile!.path);
//             logger.d('${detectedObjects?.length} Object Deteceted');
//             for(var object in detectedObjects!){
//               logger.d('Object is ${object.label} with confidence ${object.confidence} that box is ${object.bbox}');
//               var x1 = object.bbox[0]/orginalWidth;
//               var y1 = object.bbox[1]/orginalHeight;
//               var height = (object.bbox[2] - object.bbox[0])/orginalHeight;
//               var width  = (object.bbox[3] - object.bbox[1])/orginalWidth;
//               _boxes.add({
//                 "x1":x1,
//                 "y1":y1,
//                 "width":width,
//                 "height":height,

//               });
//             }
//             setState(() {
//               _setImageFileListFromFile(pickedFile);
//             });
//           } catch (e) {
//             setState(() {
//               _pickImageError = e;
//             });
//           }
//         });
//       }
//     }
//   }
//
//   @override
//   void deactivate() {
//     if (_controller != null) {
//       _controller!.setVolume(0.0);
//       _controller!.pause();
//     }
//     super.deactivate();
//   }
//
//   @override
//   void dispose() {
//     _disposeVideoController();
//     maxWidthController.dispose();
//     maxHeightController.dispose();
//     qualityController.dispose();
//     super.dispose();
//   }
//
//   Future<void> _disposeVideoController() async {
//     if (_toBeDisposed != null) {
//       await _toBeDisposed!.dispose();
//     }
//     _toBeDisposed = _controller;
//     _controller = null;
//   }
//
//   Widget _previewVideo() {
//     final Text? retrieveError = _getRetrieveErrorWidget();
//     if (retrieveError != null) {
//       return retrieveError;
//     }
//     if (_controller == null) {
//       return const Text(
//         'You have not yet picked a video',
//         textAlign: TextAlign.center,
//       );
//     }
//     return Padding(
//       padding: const EdgeInsets.all(10.0),
//       child: AspectRatioVideo(_controller),
//     );
//   }
//
//   Widget _previewImages() {
//     final Text? retrieveError = _getRetrieveErrorWidget();
//     if (retrieveError != null) {
//       return retrieveError;
//     }
//     if (_mediaFileList != null) {
//       return Semantics(
//         label: 'image_picker_example_picked_images',
//         child: ListView.builder(
//           key: UniqueKey(),
//           itemBuilder: (BuildContext context, int index) {
//             final String? mime = lookupMimeType(_mediaFileList![index].path);
//
//             // Why network for web?
//             // See https://pub.dev/packages/image_picker_for_web#limitations-on-the-web-platform
//             return Semantics(
//               label: 'image_picker_example_picked_image',
//               child: kIsWeb
//                   ? Image.network(_mediaFileList![index].path)
//                   : (mime == null || mime.startsWith('image/')
//                   ? Stack(
//                 children: [
//                   // Image
//                   Image.file(
//                       File(_mediaFileList![index].path),
//                       // width:500,
//                       // height:333,
//                       errorBuilder: (BuildContext context, Object error,
//                           StackTrace? stackTrace) {
//                         return const Center(
//                             child:
//                             Text('This image type is not supported'));
//                       },
//                     ),
//
//                   // Draw each detection box
//                   for (var box in _boxes)
//                     Positioned(
//                       left: box["x1"],
//                       top: box["y1"],
//                       width: box["width"],
//                       height: box["height"],
//                       child: Container(
//                         decoration: BoxDecoration(
//                           border: Border.all(color: Colors.red, width: 2),
//                         ),
//                       ),
//                     ),
//                 ],
//               )
//               //     ? Image.file(
//               //   File(_mediaFileList![index].path),
//               //   errorBuilder: (BuildContext context, Object error,
//               //       StackTrace? stackTrace) {
//               //     return const Center(
//               //         child:
//               //         Text('This image type is not supported'));
//               //   },
//               // )
//                   : _buildInlineVideoPlayer(index)),
//             );
//           },
//           itemCount: _mediaFileList!.length,
//         ),
//       );
//     } else if (_pickImageError != null) {
//       return Text(
//         'Pick image error: $_pickImageError',
//         textAlign: TextAlign.center,
//       );
//     } else {
//       return const Text(
//         'You have not yet picked an image.',
//         textAlign: TextAlign.center,
//       );
//     }
//   }
//
//   Widget _buildInlineVideoPlayer(int index) {
//     final VideoPlayerController controller =
//     VideoPlayerController.file(File(_mediaFileList![index].path));
//     const double volume = kIsWeb ? 0.0 : 1.0;
//     controller.setVolume(volume);
//     controller.initialize();
//     controller.setLooping(true);
//     controller.play();
//     return Center(child: AspectRatioVideo(controller));
//   }
//
//   Widget _handlePreview() {
//     if (isVideo) {
//       return _previewVideo();
//     } else {
//       return _previewImages();
//     }
//   }
//
//   Future<void> retrieveLostData() async {
//     final LostDataResponse response = await _picker.retrieveLostData();
//     if (response.isEmpty) {
//       return;
//     }
//     if (response.file != null) {
//       if (response.type == RetrieveType.video) {
//         isVideo = true;
//         await _playVideo(response.file);
//       } else {
//         isVideo = false;
//         setState(() {
//           if (response.files == null) {
//             _setImageFileListFromFile(response.file);
//           } else {
//             _mediaFileList = response.files;
//           }
//         });
//       }
//     } else {
//       _retrieveDataError = response.exception!.code;
//     }
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text(widget.title!),
//       ),
//       body: Center(
//         child: !kIsWeb && defaultTargetPlatform == TargetPlatform.android
//             ? FutureBuilder<void>(
//           future: retrieveLostData(),
//           builder: (BuildContext context, AsyncSnapshot<void> snapshot) {
//             switch (snapshot.connectionState) {
//               case ConnectionState.none:
//               case ConnectionState.waiting:
//                 return const Text(
//                   'You have not yet picked an image.',
//                   textAlign: TextAlign.center,
//                 );
//               case ConnectionState.done:
//                 return _handlePreview();
//               case ConnectionState.active:
//                 if (snapshot.hasError) {
//                   return Text(
//                     'Pick image/video error: ${snapshot.error}}',
//                     textAlign: TextAlign.center,
//                   );
//                 } else {
//                   return const Text(
//                     'You have not yet picked an image.',
//                     textAlign: TextAlign.center,
//                   );
//                 }
//             }
//           },
//         )
//             : _handlePreview(),
//       ),
//       floatingActionButton: Column(
//         mainAxisAlignment: MainAxisAlignment.end,
//         children: <Widget>[
//           Semantics(
//             label: 'image_picker_example_from_gallery',
//             child: FloatingActionButton(
//               onPressed: () {
//                 isVideo = false;
//                 _onImageButtonPressed(ImageSource.gallery, context: context);
//               },
//               heroTag: 'image0',
//               tooltip: 'Pick Image from gallery',
//               child: const Icon(Icons.photo),
//             ),
///
//           Padding(
//             padding: const EdgeInsets.only(top: 16.0),
//             child: FloatingActionButton(
//               onPressed: () {
//                 isVideo = false;
//                 _onImageButtonPressed(
//                   ImageSource.gallery,
//                   context: context,
//                   isMultiImage: true,
//                   isMedia: true,
//                 );
//               },
//               heroTag: 'multipleMedia',
//               tooltip: 'Pick Multiple Media from gallery',
//               child: const Icon(Icons.photo_library),
//             ),
///
//           Padding(
//             padding: const EdgeInsets.only(top: 16.0),
//             child: FloatingActionButton(
//               onPressed: () {
//                 isVideo = false;
//                 _onImageButtonPressed(
//                   ImageSource.gallery,
//                   context: context,
//                   isMedia: true,
//                 );
//               },
//               heroTag: 'media',
//               tooltip: 'Pick Single Media from gallery',
//               child: const Icon(Icons.photo_library),
//             ),
///
//           Padding(
//             padding: const EdgeInsets.only(top: 16.0),
//             child: FloatingActionButton(
//               onPressed: () {
//                 isVideo = false;
//                 _onImageButtonPressed(
//                   ImageSource.gallery,
//                   context: context,
//                   isMultiImage: true,
//                 );
//               },
//               heroTag: 'image1',
//               tooltip: 'Pick Multiple Image from gallery',
//               child: const Icon(Icons.photo_library),
//             ),
///
//           if (_picker.supportsImageSource(ImageSource.camera))
//             Padding(
//               padding: const EdgeInsets.only(top: 16.0),
//               child: FloatingActionButton(
//                 onPressed: () {
//                   isVideo = false;
//                   _onImageButtonPressed(ImageSource.camera, context: context);
//                 },
//                 heroTag: 'image2',
//                 tooltip: 'Take a Photo',
//                 child: const Icon(Icons.camera_alt),
//               ),
//             ),
///
//           Padding(
//             padding: const EdgeInsets.only(top: 16.0),
//             child: FloatingActionButton(
//               backgroundColor: Colors.red,
//               onPressed: () {
//                 isVideo = true;
//                 _onImageButtonPressed(ImageSource.gallery, context: context);
//               },
//               heroTag: 'video0',
//               tooltip: 'Pick Video from gallery',
//               child: const Icon(Icons.video_library),
//             ),
//           ),
///
//           if (_picker.supportsImageSource(ImageSource.camera))
//             Padding(
//               padding: const EdgeInsets.only(top: 16.0),
//               child: FloatingActionButton(
//                 backgroundColor: Colors.red,
//                 onPressed: () {
//                   isVideo = true;
//                   _onImageButtonPressed(ImageSource.camera, context: context);
//                 },
//                 heroTag: 'video1',
//                 tooltip: 'Take a Video',
//                 child: const Icon(Icons.videocam),
//               ),
//             ),
//         ],
//       ),
//     );
//   }
//
//   Text? _getRetrieveErrorWidget() {
//     if (_retrieveDataError != null) {
//       final Text result = Text(_retrieveDataError!);
//       _retrieveDataError = null;
//       return result;
//     }
//     return null;
//   }
//
//   Future<void> _displayPickImageDialog(
//       BuildContext context, bool isMulti, OnPickImageCallback onPick) async {
//     return showDialog(
//         context: context,
//         builder: (BuildContext context) {
//           return AlertDialog(
//             title: const Text('Add optional parameters'),
//             content: Column(
//               mainAxisSize: MainAxisSize.min,
//               children: <Widget>[
//                 TextField(
//                   controller: maxWidthController,
//                   keyboardType:
//                   const TextInputType.numberWithOptions(decimal: true),
//                   decoration: const InputDecoration(
//                       hintText: 'Enter maxWidth if desired'),
//                 ),
//                 TextField(
//                   controller: maxHeightController,
//                   keyboardType:
//                   const TextInputType.numberWithOptions(decimal: true),
//                   decoration: const InputDecoration(
//                       hintText: 'Enter maxHeight if desired'),
//                 ),
//                 TextField(
//                   controller: qualityController,
//                   keyboardType: TextInputType.number,
//                   decoration: const InputDecoration(
//                       hintText: 'Enter quality if desired'),
//                 ),
//                 if (isMulti)
//                   TextField(
//                     controller: limitController,
//                     keyboardType: TextInputType.number,
//                     decoration: const InputDecoration(
//                         hintText: 'Enter limit if desired'),
//                   ),
//               ],
//             ),
//             actions: <Widget>[
//               TextButton(
//                 child: const Text('CANCEL'),
//                 onPressed: () {
//                   Navigator.of(context).pop();
//                 },
//               ),
//               TextButton(
//                   child: const Text('PICK'),
//                   onPressed: () {
//                     final double? width = maxWidthController.text.isNotEmpty
//                         ? double.parse(maxWidthController.text)
//                         : null;
//                     final double? height = maxHeightController.text.isNotEmpty
//                         ? double.parse(maxHeightController.text)
//                         : null;
//                     final int? quality = qualityController.text.isNotEmpty
//                         ? int.parse(qualityController.text)
//                         : null;
//                     final int? limit = limitController.text.isNotEmpty
//                         ? int.parse(limitController.text)
//                         : null;
//                     onPick(width, height, quality, limit);
//                     Navigator.of(context).pop();
//                   }),
//             ],
//           );
//         });
//   }
// }
//
// typedef OnPickImageCallback = void Function(
//     double? maxWidth, double? maxHeight, int? quality, int? limit);
//
// class AspectRatioVideo extends StatefulWidget {
//   const AspectRatioVideo(this.controller, {super.key});
//
//   final VideoPlayerController? controller;
//
//   @override
//   AspectRatioVideoState createState() => AspectRatioVideoState();
// }
//
// class AspectRatioVideoState extends State<AspectRatioVideo> {
//   VideoPlayerController? get controller => widget.controller;
//   bool initialized = false;
//
//   void _onVideoControllerUpdate() {
//     if (!mounted) {
//       return;
//     }
//     if (initialized != controller!.value.isInitialized) {
//       initialized = controller!.value.isInitialized;
//       setState(() {});
//     }
//   }
//
//   @override
//   void initState() {
//     super.initState();
//     controller!.addListener(_onVideoControllerUpdate);
//   }
//
//   @override
//   void dispose() {
//     controller!.removeListener(_onVideoControllerUpdate);
//     super.dispose();
//   }
//
//   @override
//   Widget build(BuildContext context) {
//     if (initialized) {
//       return Center(
//         child: AspectRatio(
//           aspectRatio: controller!.value.aspectRatio,
//           child: VideoPlayer(controller!),
//         ),
//       );
//     } else {
//       return Container();
//     }
//   }
// }
