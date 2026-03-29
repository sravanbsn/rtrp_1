import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:local_auth/local_auth.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

// --- Voice Service Mock (Assuming this exists elsewhere in the app) ---
// In a real app, this would use flutter_tts or a dedicated DrishtiVoiceEngine.
class DrishtiVoice {
  static Future<void> speak(String message) async {
    print('🔊 Drishti: "$message"');
    // Implement actual TTS here
  }
}

// --- Auth States ---
enum AuthState {
  loading,
  unauthenticated,
  authenticatedNoProfile,
  authenticatedComplete,
  authenticatedGuardian,
}

// --- Error Classes ---
class AuthException implements Exception {
  final String message;
  final String code;
  AuthException(this.message, [this.code = 'unknown']);
  @override
  String toString() => message;
}

// --- Provider Definitions ---
final authServiceProvider = Provider<AuthService>((ref) {
  return AuthService();
});

final authStateProvider = StreamProvider<AuthState>((ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateStream;
});

// --- Main Auth Service ---
class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
  final LocalAuthentication _localAuth = LocalAuthentication();
  final FlutterSecureStorage _secureStorage = const FlutterSecureStorage();

  static const String _biometricKey = 'drishti_biometric_token';
  String? _verificationId;
  Timer? _otpTimer;

  // --- Auth State Stream ---
  Stream<AuthState> get authStateStream {
    return _auth.authStateChanges().asyncMap((user) async {
      if (user == null) {
        return AuthState.unauthenticated;
      }

      // Check user profile in Firestore
      try {
        final doc = await _db.collection('users').doc(user.uid).get();
        if (!doc.exists) {
          return AuthState.authenticatedNoProfile;
        }

        final role = doc.data()?['profile']?['role'] as String?;
        if (role == 'guardian') {
          return AuthState.authenticatedGuardian;
        }
        
        return AuthState.authenticatedComplete;
      } catch (e) {
        print('Error fetching user profile: $e');
        // Default to no profile if error occurs during fetch, forcing profile setup
        return AuthState.authenticatedNoProfile;
      }
    });
  }

  // --- 1. Phone OTP Authentication ---

  Future<void> signInWithPhone(String phoneNumber) async {
    try {
      // 1. Format number (Extremely basic validation)
      String formattedNumber = phoneNumber.trim();
      if (!formattedNumber.startsWith('+91')) {
        formattedNumber = '+91$formattedNumber'; 
      }

      await DrishtiVoice.speak("Number check kar rahi hoon. Kripya rukein.");

      // 2. Call Firebase verification
      await _auth.verifyPhoneNumber(
        phoneNumber: formattedNumber,
        timeout: const Duration(seconds: 60),
        
        verificationCompleted: (PhoneAuthCredential credential) async {
          // Auto-resolution (on some Android devices)
          await _signInWithCredential(credential);
          await DrishtiVoice.speak("Phone verify ho gaya. Andar chalte hain.");
        },
        
        verificationFailed: (FirebaseAuthException e) async {
          if (e.code == 'invalid-phone-number') {
            await DrishtiVoice.speak("Number sahi nahi hai. Dobara boliye.");
          } else if (e.code == 'too-many-requests') {
            await DrishtiVoice.speak("Thoda ruko. Baad mein try karein.");
          } else if (e.code == 'network-request-failed') {
            await DrishtiVoice.speak("Internet nahi hai. Check karein.");
          } else {
            await DrishtiVoice.speak("Kuch galat hua. Fir se try kijiye.");
          }
          throw AuthException(e.message ?? 'Verification failed', e.code);
        },
        
        codeSent: (String verificationId, int? resendToken) async {
          _verificationId = verificationId;
          await DrishtiVoice.speak("OTP bheja. Boliye code.");
          
          // Setup timeout for OTP entry
          _otpTimer?.cancel();
          _otpTimer = Timer(const Duration(seconds: 60), () {
             DrishtiVoice.speak("Samay khatam. Naya code bhejti hoon.");
             // Note: In real app, trigger resend logic automatically or prompt user
          });
        },
        
        codeAutoRetrievalTimeout: (String verificationId) {
          _verificationId = verificationId;
        },
      );
    } catch (e) {
       print('signInWithPhone Error: $e');
       rethrow;
    }
  }

  Future<void> verifyOTP(String otpCode) async {
    if (_verificationId == null) {
      await DrishtiVoice.speak("Session khatam. Fir se number daaliye.");
      throw AuthException('Session expired or undefined verification ID');
    }

    _otpTimer?.cancel();

    try {
      PhoneAuthCredential credential = PhoneAuthProvider.credential(
        verificationId: _verificationId!,
        smsCode: otpCode.trim(),
      );

      await _signInWithCredential(credential);
      await DrishtiVoice.speak("OTP Sahi hai.");
      
      // Auto-setup biometric token for future logins
      await _storeBiometricToken();

    } on FirebaseAuthException catch (e) {
      if (e.code == 'invalid-verification-code') {
        await DrishtiVoice.speak("Code galat hai. Dobara boliye.");
      } else if (e.code == 'session-expired') {
        await DrishtiVoice.speak("Samay khatam. Naya code bhejti hoon.");
      } else {
        await DrishtiVoice.speak("Kuch galat hua. Fir se try karein.");
      }
      throw AuthException(e.message ?? 'Invalid OTP', e.code);
    }
  }

  // --- 2. Google Sign-In ---

  Future<void> signInWithGoogle() async {
    try {
      await DrishtiVoice.speak("Google account se login kar rahi hoon.");
      
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        // User canceled the sign-in flow
        await DrishtiVoice.speak("Aapne login cancel kar diya.");
        return;
      }

      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;

      final OAuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );

      await _signInWithCredential(credential);
      await DrishtiVoice.speak("Google login safal raha.");
      
      await _storeBiometricToken();

    } catch (e) {
      await DrishtiVoice.speak("Google login fail hua.");
      print('signInWithGoogle Error: $e');
      throw AuthException('Google Sign In failed');
    }
  }

  // --- 3. Biometric Authentication ---

  Future<bool> setupBiometric() async {
    try {
      bool canCheckBiometrics = await _localAuth.canCheckBiometrics;
      bool isDeviceSupported = await _localAuth.isDeviceSupported();

      if (!canCheckBiometrics || !isDeviceSupported) {
        await DrishtiVoice.speak("Aapka device fingerprint support nahi karta.");
        return false;
      }

      bool authenticated = await _localAuth.authenticate(
        localizedReason: 'Drishti: Apna fingerprint lagayein token save karne ke liye',
        options: const AuthenticationOptions(
          stickyAuth: true,
          biometricOnly: true, // Prefer biometric over PIN for ease of use
        ),
      );

      if (authenticated) {
        await _storeBiometricToken();
        await DrishtiVoice.speak("Fingerprint set ho gaya.");
        return true;
      }
      
      return false;
    } catch (e) {
      print('setupBiometric Error: $e');
      return false;
    }
  }

  Future<void> authenticateWithBiometric() async {
    int attempts = 0;
    const int maxAttempts = 3;

    try {
       String? token = await _secureStorage.read(key: _biometricKey);
       if (token == null) {
          throw AuthException("Biometric setup nahi hai. Pehle login karein.");
       }

      while (attempts < maxAttempts) {
        bool authenticated = await _localAuth.authenticate(
          localizedReason: 'Drishti: Kripya apna fingerprint lagayein',
          options: const AuthenticationOptions(stickyAuth: true),
        );

        if (authenticated) {
          // In a highly secure app, the token stored would be used to sign a
          // challenge from the server, or retrieve cached credentials.
          // For Firebase, if the token is valid, we assume the user is still 
          // logged in (Firebase persists auth state automatically).
          // We just verify they are who they say they are locally.
          
          if (_auth.currentUser != null) {
             // Force token refresh to ensure active session
             await _auth.currentUser!.getIdToken(true);
             await DrishtiVoice.speak("Pehchaan ho gayi. Andar chalte hain.");
             return;
          } else {
             await DrishtiVoice.speak("Session expire ho gaya. OTP se login karein.");
             // Here we could potentially use cached creds to auto-login,
             // but forcing OTP is safer on session expiry.
             await signOut();
             return;
          }
        } else {
           attempts++;
           if (attempts < maxAttempts) {
              await DrishtiVoice.speak("Fingerprint match nahi hua. Ek baar aur try karein.");
           }
        }
      }

      await DrishtiVoice.speak("Fingerprint fail. Kripya phone number se login karein.");
      throw AuthException('Biometric failed maximum attempts');

    } catch (e) {
      print('authenticateWithBiometric Error: $e');
      rethrow;
    }
  }

  // --- Internal Helper: Process Credential ---
  Future<void> _signInWithCredential(AuthCredential credential) async {
    try {
      UserCredential userCredential = await _auth.signInWithCredential(credential);
      // State stream will handle routing based on profile existence
    } catch (e) {
       print('_signInWithCredential Error: $e');
       rethrow;
    }
  }

  Future<void> _storeBiometricToken() async {
     // Generate a stable token for this device/user combo
     if (_auth.currentUser != null) {
        final token = "${_auth.currentUser!.uid}_${DateTime.now().millisecondsSinceEpoch}";
        await _secureStorage.write(key: _biometricKey, value: token);
     }
  }


  // --- 4. User Profile Creation ---

  Future<void> createUserProfile({
    required String name,
    required String phone,
    required String role, // "user" or "guardian"
    String language = "hindi",
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    try {
      WriteBatch batch = _db.batch();
      DocumentReference userRef = _db.collection('users').doc(user.uid);

      final now = FieldValue.serverTimestamp();

      // Base Profile
      batch.set(userRef, {
        'profile': {
          'name': name,
          'phone': phone,
          'role': role,
          'language': language,
          'photo_url': user.photoURL ?? '',
          'created_at': now,
          'last_active': now,
          'app_version': '1.0.0', // dynamic in prod
        },
        'adaptive_profile': {
          'warning_threshold': 40,
          'override_threshold': 75,
          'sos_timeout_seconds': 45,
          'haptic_intensity': 'high',
          'alert_voice_style': 'moderate',
          'total_sessions': 0,
          'total_distance_km': 0,
          'total_hazards_avoided': 0,
          'total_overrides': 0,
          'threshold_history': [],
          'last_updated': now,
        },
        'settings': {
          'wake_word': 'Drishti',
          'language': language,
          'night_mode': 'auto',
          'route_learning': true,
          'crowd_warnings': true,
          'screen_off_listening': true,
          'silence_zones': [],
        }
      });

      // If Guardian, create separate index document
      if (role == 'guardian') {
        DocumentReference guardianRef = _db.collection('guardians').doc(user.uid);
        batch.set(guardianRef, {
          'user_id': '', // Will be linked later
          'name': name,
          'phone': phone,
          'email': user.email ?? '',
          'relation': 'unspecified',
          'active': true,
          'fcm_tokens': [],
          'notification_prefs': {
            'sos': true, // Locked
            'override': true,
            'session_updates': false,
            'zone_alerts': true,
            'battery_low': true,
            'channels': {
              'push': true,
              'sms': false,
              'whatsapp': false,
              'email': false,
            }
          },
          'created_at': now,
        });
      }

      await batch.commit();
      await DrishtiVoice.speak("Profile ban gayi hai. Swagat hai $name.");

    } catch (e) {
      print('createUserProfile Error: $e');
      await DrishtiVoice.speak("Profile save nahi ho payi. Network check karein.");
      throw AuthException("Failed to create profile");
    }
  }

  // --- 5. Guardian Linking ---

  Future<void> linkGuardianToUser(String guardianPhone) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("Not authenticated");

    try {
      await DrishtiVoice.speak("Guardian search kar rahi hoon.");

      // Format phone
      String formattedPhone = guardianPhone.trim();
      if (!formattedPhone.startsWith('+91')) formattedPhone = '+91$formattedPhone';

      // 1. Find guardian in users collection
      final querySnapshot = await _db
          .collection('users')
          .where('profile.phone', isEqualTo: formattedPhone)
          .where('profile.role', isEqualTo: 'guardian')
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        await DrishtiVoice.speak("Is number par koi guardian account nahi mila.");
        return;
      }

      final guardianDoc = querySnapshot.docs.first;
      final guardianId = guardianDoc.id;
      final guardianName = guardianDoc.data()['profile']['name'] ?? 'Guardian';

      // 2. Update Guardian Document
      await _db.collection('guardians').doc(guardianId).update({
        'user_id': user.uid,
      });

      // 3. (Optional but recommended) Add reference in User doc
      // await _db.collection('users').doc(user.uid).update({'linked_guardian': guardianId});

      await DrishtiVoice.speak("$guardianName ko aapka guardian set kar diya gaya hai.");
      
      // Note: Trigger FCM notification here to guardianId
      // "Aapko Drishti-Link par guardian assign kiya gaya hai."

    } catch (e) {
      print('linkGuardianToUser Error: $e');
      await DrishtiVoice.speak("Guardian link karne mein problem aayi.");
    }
  }

  // --- 6. Sign Out ---

  Future<void> signOut() async {
    try {
      await _auth.signOut();
      await _googleSignIn.signOut();
      await _secureStorage.delete(key: _biometricKey);
      await DrishtiVoice.speak("Aap log out ho gaye hain.");
    } catch (e) {
      print('signOut Error: $e');
    }
  }
}
