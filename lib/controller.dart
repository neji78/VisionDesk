import 'dart:nativewrappers/_internal/vm/lib/typed_data_patch.dart';
import 'dart:ui';
import 'package:http_parser/http_parser.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'dart:convert';

import 'model.dart';

class YoloDetectionController {
  final String serverUrl;

  YoloDetectionController({required this.serverUrl});

  Future<List<DetectionResult>> detectObjects(String path) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/detect'),
      );

      request.files.add(
        await http.MultipartFile.fromPath('image', path),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final decoded = json.decode(responseData) as List;

        return decoded
            .map((item) => DetectionResult.fromJson(item))
            .toList();
      } else {
        throw Exception('Server responded with ${response.statusCode}');
      }
    } catch (e) {
      rethrow; // Or handle error gracefully
    }
  }

  Future<List<DetectionResult>> detectObjectsFromBytes(Uint8List bytes, {String filename = 'image.jpg'}) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse('$serverUrl/detect'),
      );

      request.files.add(
        http.MultipartFile.fromBytes(
          'image',
          bytes as List<int>,
          filename: filename,
          contentType: MediaType('image', 'jpeg'),
        ),
      );

      var response = await request.send();

      if (response.statusCode == 200) {
        final responseData = await response.stream.bytesToString();
        final decoded = json.decode(responseData) as List;

        return decoded
            .map((item) => DetectionResult.fromJson(item))
            .toList();
      } else {
        throw Exception('Server responded with ${response.statusCode}');
      }
    } catch (e) {
      rethrow;
    }
  }
}
