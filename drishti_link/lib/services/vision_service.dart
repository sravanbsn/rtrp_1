import 'dart:convert';
import 'package:camera/camera.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';

class VisionResponse {
  final int overallPc;
  final String ttsMessage;
  final bool shouldOverride;
  final List<dynamic> hazards;

  VisionResponse({
    required this.overallPc,
    required this.ttsMessage,
    required this.shouldOverride,
    required this.hazards,
  });

  factory VisionResponse.fromJson(Map<String, dynamic> json) {
    return VisionResponse(
      overallPc: json['overall_pc'] ?? 0,
      ttsMessage: json['tts_message'] ?? '',
      shouldOverride: json['should_override'] ?? false,
      hazards: json['hazards'] ?? [],
    );
  }
}

class VisionService {
  /// Sends the captured image to the production Railway backend.
  static Future<VisionResponse?> analyzeImage({
    required XFile image,
    required String userId,
    required String sessionId,
    double lat = 0.0,
    double lng = 0.0,
  }) async {
    try {
      var request = http.MultipartRequest(
        'POST',
        Uri.parse(ApiConstants.analyzeEndpoint),
      );

      request.fields['user_id'] = userId;
      request.fields['session_id'] = sessionId;
      request.fields['lat'] = lat.toString();
      request.fields['lng'] = lng.toString();

      var multipartFile = await http.MultipartFile.fromPath(
        'frame',
        image.path,
      );
      request.files.add(multipartFile);

      var streamedResponse = await request.send();
      var response = await http.Response.fromStream(streamedResponse);

      if (response.statusCode == 200) {
        var decoded = json.decode(response.body);
        return VisionResponse.fromJson(decoded);
      } else {
        print('VisionService failed: ${response.statusCode} - ${response.body}');
        return null;
      }
    } catch (e) {
      print('VisionService Error: $e');
      return null;
    }
  }
}
