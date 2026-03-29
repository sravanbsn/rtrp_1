import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:uuid/uuid.dart';

// --- Voice Service Mock ---
class DrishtiVoice {
  static Future<void> speak(String message) async {
    print('🔊 Drishti: "$message"');
  }
}

// --- Notification Service Mock ---
// In a real app, this calls a cloud function or backend API
class NotificationService {
  static Future<void> sendToGuardian(String guardianId, String title, String body, {bool highPriority = false}) async {
    print('📱 FCM to Guardian [$guardianId]: $title - $body (High Priority: $highPriority)');
  }

  static Future<void> triggerBackendSOS(String userId, String sessionId, GeoPoint location) async {
    print('🚨 Triggering Backend SOS API for user $userId');
  }
}

// --- Models ---
class Route {
  final String id;
  final String name;
  final double distanceKm;
  final int safetyScore;
  final List<dynamic> knownHazards;
  Route({required this.id, required this.name, required this.distanceKm, required this.safetyScore, required this.knownHazards});
}

class LiveNavigationData {
  final String status;
  final double pcScore;
  final String decision;
  final String currentHazard;
  final Map<String, dynamic>? lastAlert;
  final double lat;
  final double lng;

  LiveNavigationData.fromMap(Map<dynamic, dynamic> map)
      : status = map['status'] ?? 'unknown',
        pcScore = (map['current_pc_score'] ?? 0).toDouble(),
        decision = map['current_decision'] ?? 'CLEAR',
        currentHazard = map['current_hazard'] ?? '',
        lastAlert = map['last_alert'] != null ? Map<String, dynamic>.from(map['last_alert']) : null,
        lat = (map['last_location']?['lat'] ?? 0).toDouble(),
        lng = (map['last_location']?['lng'] ?? 0).toDouble();
}


class FirebaseService {
  static final FirebaseService _instance = FirebaseService._internal();
  factory FirebaseService() => _instance;
  FirebaseService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseDatabase _rtdb = FirebaseDatabase.instance;
  final Uuid _uuid = const Uuid();

  // In-memory Area Memory cache for current session
  final Map<String, Map<String, dynamic>> _areaMemoryCache = {};

  // --- Initialization ---

  Future<void> initializeOfflinePersistence() async {
    try {
      // Configure Firestore offline persistence (100MB cache)
      _firestore.settings = const Settings(
        persistenceEnabled: true,
        cacheSizeBytes: 104857600, // 100 MB
      );

      // Configure RTDB offline persistence
      _rtdb.setPersistenceEnabled(true);
      _rtdb.setPersistenceCacheSizeBytes(10485760); // 10 MB

      // Keep specific critical paths synced when app is in foreground
      _rtdb.ref('admin/broadcasts').keepSynced(true);
      
      print('✅ Firebase Offline Persistence Enabled');
    } catch (e) {
      print('❌ Failed to enable offline persistence: $e');
    }
  }

  // --- 1. Session Management ---

  Future<String> startNavigationSession(String userId, String guardianId, GeoPoint startLocation) async {
    final String sessionId = _uuid.v4();
    final now = FieldValue.serverTimestamp();

    // 1. Create Firestore session document
    await _firestore.collection('sessions').doc(sessionId).set({
      'user_id': userId,
      'guardian_id': guardianId,
      'start_time': now,
      'status': 'active',
      'start_location': startLocation,
      'route_points': [startLocation],
      'summary': {
        'alerts_count': 0,
        'overrides_count': 0,
        'hazards_avoided': 0,
        'false_positives': 0,
        'sos_triggered': false,
      }
    });

    // 2. Initialize Realtime DB live tracking node
    await _rtdb.ref('live_sessions/$sessionId').set({
      'user_id': userId,
      'guardian_id': guardianId,
      'status': 'active',
      'current_pc_score': 0,
      'current_decision': 'CLEAR',
      'current_hazard': '',
      'last_location': {
        'lat': startLocation.latitude,
        'lng': startLocation.longitude,
        'timestamp': ServerValue.timestamp,
        'accuracy': 10.0,
      },
      'device_info': {
        'battery_level': 100, // Replace with actual platform battery check
        'gps_accuracy': 'HIGH',
        'ai_status': 'ONLINE',
        'connection': '4G/5G'
      },
      'updated_at': ServerValue.timestamp,
    });

    // Handle connection state for offline cleanup
    _rtdb.ref('live_sessions/$sessionId/status').onDisconnect().set('offline');

    // 3. Send FCM to guardian
    await NotificationService.sendToGuardian(
      guardianId, 
      "Navigation Started", 
      "🟢 Arjun ne navigation shuru kiya."
    );

    // Clear local cache for new session
    _areaMemoryCache.clear();

    return sessionId;
  }

  Future<void> updateLiveNavigation({
    required String sessionId,
    required double lat,
    required double lng,
    required double accuracy,
    required double pcScore,
    required String decision,
    required String currentHazard,
  }) async {
    // Delta updates to RTDB (Speed-critical)
    Map<String, dynamic> updates = {
      'last_location/lat': lat,
      'last_location/lng': lng,
      'last_location/accuracy': accuracy,
      'last_location/timestamp': ServerValue.timestamp,
      'current_pc_score': pcScore,
      'current_decision': decision,
      'current_hazard': currentHazard,
      'updated_at': ServerValue.timestamp,
    };

    try {
      await _rtdb.ref('live_sessions/$sessionId').update(updates);
    } catch (e) {
      print('⚠️ RTDB live update failed (Will queue if offline): $e');
    }
  }

  Future<void> logNavigationAlert({
    required String sessionId,
    required String userId,
    required String guardianId,
    required Map<String, dynamic> alertData,
  }) async {
    final now = FieldValue.serverTimestamp();
    final type = alertData['type'] as String;

    // 1. Write to Firestore 'alerts' collection
    final alertRef = _firestore.collection('alerts').doc();
    final fullAlertData = {
      ...alertData,
      'session_id': sessionId,
      'user_id': userId,
      'timestamp': now,
      'guardian_notified': false,
    };
    
    // Batch write to update session summary simultaneously
    WriteBatch batch = _firestore.batch();
    batch.set(alertRef, fullAlertData);
    
    // Increment session counters
    final sessionRef = _firestore.collection('sessions').doc(sessionId);
    batch.update(sessionRef, {
      'summary.alerts_count': FieldValue.increment(1),
      if (type == 'override') 'summary.overrides_count': FieldValue.increment(1),
    });

    await batch.commit();

    // 2. Update RTDB last_alert for Guardian stream
    await _rtdb.ref('live_sessions/$sessionId/last_alert').set({
      'type': type,
      'message': alertData['plain_description'] ?? '',
      'timestamp': ServerValue.timestamp,
    });

    // 3. Trigger immediate notification for high risk
    if (type == 'override') {
      await NotificationService.sendToGuardian(
        guardianId,
        "Emergency Override",
        "🔴 Drishti ne Arjun ko roka: ${alertData['plain_description']}",
        highPriority: true,
      );
      // Update firestore to mark as notified
      alertRef.update({'guardian_notified': true});
    } else if (type == 'sos') {
      await _triggerSOSPipeline(userId, sessionId, guardianId, alertData['location'], alertData['plain_description']);
    }
  }

  Future<void> endNavigationSession(String userId, String guardianId, String sessionId, List<GeoPoint> routePoints) async {
    final now = FieldValue.serverTimestamp();

    // Calculate distance (Haversine simple estimation)
    double distanceKm = _calculateTotalDistance(routePoints);
    
    // Fetch session data to compute duration and safety score
    final sessionDoc = await _firestore.collection('sessions').doc(sessionId).get();
    final data = sessionDoc.data();
    
    double durationMins = 0;
    int overrides = 0;
    int falsePositives = 0;
    
    if (data != null) {
      final startTime = (data['start_time'] as Timestamp?)?.toDate() ?? DateTime.now();
      durationMins = DateTime.now().difference(startTime).inMinutes.toDouble();
      
      final summary = data['summary'] ?? {};
      overrides = summary['overrides_count'] ?? 0;
      falsePositives = summary['false_positives'] ?? 0;
    }

    // Base 100, minus penalties
    int safetyScore = 100 - (overrides * 5) - (falsePositives * 2);
    safetyScore = safetyScore.clamp(0, 100);

    // 1. Update Firestore session
    WriteBatch batch = _firestore.batch();
    batch.update(_firestore.collection('sessions').doc(sessionId), {
      'end_time': now,
      'status': 'ended',
      'end_location': routePoints.isNotEmpty ? routePoints.last : null,
      'route_points': routePoints, // In prod, consider downsampling this array if large
      'summary.distance_km': distanceKm,
      'summary.duration_minutes': durationMins,
      'summary.safety_score': safetyScore,
    });

    // 2. Update User total stats
    batch.update(_firestore.collection('users').doc(userId), {
      'adaptive_profile.total_sessions': FieldValue.increment(1),
      'adaptive_profile.total_distance_km': FieldValue.increment(distanceKm),
    });

    await batch.commit();

    // 3. Remove from RTDB (or mark ended)
    await _rtdb.ref('live_sessions/$sessionId/status').set('ended');
    // Optionally remove entirely to save space: await _rtdb.ref('live_sessions/$sessionId').remove();

    // 4. Notify Guardian
    String distStr = distanceKm.toStringAsFixed(2);
    await NotificationService.sendToGuardian(
      guardianId, 
      "Navigation Ended", 
      "🏠 Arjun safely pauhch gaye. $distStr km chale."
    );
  }

  // --- 2. SOS Pipeline ---

  Future<String> _triggerSOSPipeline(String userId, String sessionId, String guardianId, GeoPoint location, String reason) async {
    final String sosId = _uuid.v4();
    final now = FieldValue.serverTimestamp();

    // 1. Write SOS event to Firestore
    await _firestore.collection('sos_events').doc(sosId).set({
      'user_id': userId,
      'session_id': sessionId,
      'triggered_at': now,
      'trigger_reason': reason,
      'location': location,
      'resolved': false,
    });

    // 2. Update session status globally
    await _firestore.collection('sessions').doc(sessionId).update({'summary.sos_triggered': true, 'status': 'sos'});
    await _rtdb.ref('live_sessions/$sessionId/status').set('sos');

    // 3. High Priority FCM
    await NotificationService.sendToGuardian(
      guardianId,
      "🚨 SOS ALERT",
      "Arjun ne SOS dabaya hai! Turant check karein.",
      highPriority: true,
    );

    // 4. Call backend API for SMS/WhatsApp
    await NotificationService.triggerBackendSOS(userId, sessionId, location);

    // 5. Start Voice Reassurance loop in app
    _startReassuranceLoop();

    return sosId;
  }

  Future<String> triggerSOSManual(String userId, String sessionId, String guardianId, GeoPoint location) async {
    return _triggerSOSPipeline(userId, sessionId, guardianId, location, "Manual Button Press");
  }

  Timer? _reassuranceTimer;
  void _startReassuranceLoop() {
    _reassuranceTimer?.cancel();
    DrishtiVoice.speak("Ghabraiye mat. Guardian ko bata diya gaya hai.");
    _reassuranceTimer = Timer.periodic(const Duration(seconds: 15), (timer) {
      DrishtiVoice.speak("Guardian se sampark kiya ja raha hai. Mai yahan hoon.");
    });
  }

  Future<void> cancelSOS(String sosId, String sessionId, String userId, String guardianId) async {
    _reassuranceTimer?.cancel();

    // Update Firestore
    await _firestore.collection('sos_events').doc(sosId).update({
      'resolved': true,
      'resolution_type': 'user_cancelled',
      'cancelled_at': FieldValue.serverTimestamp(),
    });

    // Restore Session
    await _firestore.collection('sessions').doc(sessionId).update({'status': 'active'});
    await _rtdb.ref('live_sessions/$sessionId/status').set('active');

    // Notify Guardian
    await NotificationService.sendToGuardian(
      guardianId,
      "SOS Cancelled",
      "Arjun ne SOS cancel kiya hai. Sab theek hai.",
    );

    await DrishtiVoice.speak("SOS cancel kar diya gaya hai. Navigation shuru kar rahi hoon.");
  }


  // --- 3. Guardian Real-time Streams ---

  Stream<LiveNavigationData?> watchUserLiveData(String sessionId) {
    if (sessionId.isEmpty) return const Stream.empty();

    final controller = StreamController<LiveNavigationData?>();
    Timer? offlineTimer;

    final subscription = _rtdb.ref('live_sessions/$sessionId').onValue.listen((event) {
      if (event.snapshot.value != null) {
        final data = event.snapshot.value as Map<dynamic, dynamic>;
        controller.add(LiveNavigationData.fromMap(data));

        // Handle offline state tracking from Guardian side
        offlineTimer?.cancel();
        offlineTimer = Timer(const Duration(seconds: 10), () {
          // If 10s pass without RTDB update, user is likely offline or lost GPS
          if (!controller.isClosed) {
            Map<String, dynamic> offlineMap = Map<String, dynamic>.from(data);
            offlineMap['status'] = 'offline';
            controller.add(LiveNavigationData.fromMap(offlineMap));
          }
        });
      } else {
        controller.add(null);
      }
    }, onError: (error) {
       controller.addError(error);
    });

    controller.onCancel = () {
      subscription.cancel();
      offlineTimer?.cancel();
    };

    return controller.stream;
  }

  Stream<List<Map<String, dynamic>>> watchUserAlerts(String sessionId) {
    if (sessionId.isEmpty) return const Stream.empty();

    return _firestore.collection('alerts')
        .where('session_id', isEqualTo: sessionId)
        .orderBy('timestamp', descending: true)
        .limit(50)
        .snapshots()
        .map((snapshot) => snapshot.docs.map((d) => {'id': d.id, ...d.data()}).toList());
  }


  // --- 4. Route Management ---

  Future<void> saveRoute({
    required String userId,
    required String sessionId,
    required List<GeoPoint> routePoints,
    required String name,
  }) async {
    if (routePoints.isEmpty) return;

    double distanceKm = _calculateTotalDistance(routePoints);
    // Rough estimate: walking speed 4.5 km/h -> 1 km = ~13.3 mins
    int estimatedTimeMins = (distanceKm * 13.3).round();

    // Fetch alerts for safety score and known hazards
    final alertsSnap = await _firestore.collection('alerts').where('session_id', isEqualTo: sessionId).get();
    
    int overrides = alertsSnap.docs.where((d) => d.data()['type'] == 'override').length;
    int safetyScore = (100 - (overrides * 5)).clamp(0, 100);

    // Extract unique hazards from alerts
    Set<String> hazards = {};
    for (var doc in alertsSnap.docs) {
      if ((doc.data()['hazard_type'] ?? '').toString().isNotEmpty) {
        hazards.add(doc.data()['hazard_type']);
      }
    }

    final routeRef = _firestore.collection('routes').doc();
    await routeRef.set({
      'user_id': userId,
      'name': name,
      'created_at': FieldValue.serverTimestamp(),
      'last_used': FieldValue.serverTimestamp(),
      'times_used': 1,
      'favorite': false,
      'points': routePoints, // Storing dense points, consider downsampling
      'distance_km': distanceKm,
      'estimated_time_minutes': estimatedTimeMins,
      'safety_score': safetyScore,
      'known_hazards': hazards.toList(),
      'time_of_day_pattern': [DateTime.now().hour]
    });
  }

  Future<List<Route>> getUserRoutes(String userId) async {
    try {
      // GetOptions allows querying cache first if offline
      QuerySnapshot snapshot = await _firestore.collection('routes')
          .where('user_id', isEqualTo: userId)
          .orderBy('last_used', descending: true)
          .get(const GetOptions(source: Source.serverAndCache));

      return snapshot.docs.map((doc) {
        final data = doc.data() as Map<String, dynamic>;
        return Route(
          id: doc.id,
          name: data['name'] ?? 'Unnamed Route',
          distanceKm: (data['distance_km'] ?? 0.0).toDouble(),
          safetyScore: (data['safety_score'] ?? 100).toInt(),
          knownHazards: List<dynamic>.from(data['known_hazards'] ?? []),
        );
      }).toList();
    } catch (e) {
      print('getUserRoutes Error: $e');
      return [];
    }
  }


  // --- 5. Area Memory ---

  Future<void> updateAreaMemory(GeoPoint location, String hazardType, double confidence) async {
    // Generate 10m precision geohash (roughly 7 characters)
    String geoHash = _encodeGeohash(location.latitude, location.longitude, 7);
    String compositeKey = '${geoHash}_$hazardType';

    // 1. Update in-memory cache to prevent spamming Firestore
    if (_areaMemoryCache.containsKey(compositeKey)) {
      final cacheData = _areaMemoryCache[compositeKey]!;
      // Throttle writes to once every 5 minutes per hazard per cell
      if (DateTime.now().difference(cacheData['last_write']).inMinutes < 5) {
        return;
      }
    }

    final docRef = _firestore.collection('area_memory').doc(compositeKey);

    try {
      await _firestore.runTransaction((transaction) async {
        final snapshot = await transaction.get(docRef);

        if (!snapshot.exists) {
          transaction.set(docRef, {
            'location': location, // Store actual lat/lng
            'hazard_type': hazardType,
            'detection_count': 1,
            'first_detected': FieldValue.serverTimestamp(),
            'last_detected': FieldValue.serverTimestamp(),
            'verified': false,
            'verified_by': '',
            'severity': confidence > 0.8 ? 'high' : 'medium',
            'active': true,
          });
        } else {
          int count = (snapshot.data()?['detection_count'] ?? 0) + 1;
          transaction.update(docRef, {
            'detection_count': count,
            'last_detected': FieldValue.serverTimestamp(),
            // If seen >=3 times on different sessions, it becomes a "known hazard" backend processing
          });
        }
      });

      // Update local cache
      _areaMemoryCache[compositeKey] = {
        'last_write': DateTime.now(),
        'hazard': hazardType
      };

    } catch (e) {
      print('⚠️ Failed to update area memory (Will queue offline): $e');
    }
  }

  // --- 6. Adaptive Profile Sync ---

  Future<void> updateAdaptiveProfile(String userId, Map<String, dynamic> thresholdChanges, String reason) async {
    try {
      final docRef = _firestore.collection('users').doc(userId);
      final now = FieldValue.serverTimestamp();

      // Ensure we don't change more than 5 points is a client side / backend validator responsibility, 
      // but we append the history here.
      
      Map<String, dynamic> historyEntry = {
        ...thresholdChanges,
        'reason': reason,
        'timestamp': now,
      };

      await docRef.update({
        'adaptive_profile.last_updated': now,
        'adaptive_profile.threshold_history': FieldValue.arrayUnion([historyEntry]),
        // Update the actual threshold fields dynamically
        for (var entry in thresholdChanges.entries) 
           'adaptive_profile.${entry.key}': entry.value
      });

    } catch (e) {
      print('⚠️ Failed to sync adaptive profile: $e');
    }
  }

  // --- Utils ---

  double _calculateTotalDistance(List<GeoPoint> points) {
    if (points.length < 2) return 0.0;
    double total = 0.0;
    for (int i = 0; i < points.length - 1; i++) {
        total += _haversineDistance(
          points[i].latitude, points[i].longitude, 
          points[i+1].latitude, points[i+1].longitude,
        );
    }
    return total;
  }

  double _haversineDistance(double lat1, double lon1, double lat2, double lon2) {
    const R = 6371.0; // Earth radius in km
    final dLat = _toRadians(lat2 - lat1);
    final dLon = _toRadians(lon2 - lon1);
    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
              math.cos(_toRadians(lat1)) * math.cos(_toRadians(lat2)) *
              math.sin(dLon / 2) * math.sin(dLon / 2);
    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return R * c;
  }

  double _toRadians(double degree) {
    return degree * math.pi / 180;
  }

  // Simplified geohash function representation
  String _encodeGeohash(double lat, double lng, int precision) {
    // Basic implementation for illustration. 
    // In production, use the `geohash` dart package.
    int latInt = (lat * 1000).round();
    int lngInt = (lng * 1000).round();
    return "${latInt}_$lngInt"; // Fallback to grid grouping if geohash lib missing
  }

}
