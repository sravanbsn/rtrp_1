import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants/api_constants.dart';

class SosService {
  // Hardcoded demo IDs — no auth lookup needed for lean integration.
  static const String _demoUserId     = 'demo_user_123';
  static const String _demoGuardianId = 'guardian_demo_id';

  /// Triggers a Lean SOS on the Railway backend.
  /// Returns true on HTTP 201, false on any error.
  static Future<bool> triggerSOS({
    required double lat,
    required double lng,
    String? userId,
    String? sessionId,
    String locationLabel = 'Current Location',
    List<String>? guardianIds,
  }) async {
    final resolvedUserId     = userId?.isNotEmpty == true ? userId! : _demoUserId;
    final resolvedGuardians  = (guardianIds?.isNotEmpty == true)
        ? guardianIds!
        : [_demoGuardianId];

    final payload = {
      'user_id':        resolvedUserId,
      'session_id':     sessionId,
      'lat':            lat,
      'lng':            lng,
      'location_label': locationLabel,
      'triggered_by':   'user',
      'guardian_ids':   resolvedGuardians,
    };

    debugPrint('[SosService] ▶ POST ${ApiConstants.sosTriggerEndpoint}');
    debugPrint('[SosService]   payload: ${json.encode(payload)}');

    try {
      final response = await http
          .post(
            Uri.parse(ApiConstants.sosTriggerEndpoint),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 10));

      debugPrint('[SosService] ◀ HTTP ${response.statusCode}: ${response.body}');
      return response.statusCode == 201;
    } catch (e, st) {
      debugPrint('[SosService] ✕ Error: $e\n$st');
      return false;
    }
  }
}
