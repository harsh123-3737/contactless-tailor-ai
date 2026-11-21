import 'dart:convert';

import 'auth_screen.dart';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'shop_screen.dart';
import 'main.dart'; // InstructionsScreen mate

class UserSession {
  static String baseUrl = 'http://10.186.76.227:8000'; // <-- Tamaro IPv4 mukjo
  static int? userId;
  static String userName = '';
  static String gender = 'Male';

  /// Scan measurements database ma save kare che
  static Future<bool> saveMeasurement({
    required double shoulderCm,
    required double hipCm,
    required double sleeveCm,
    required double legCm,
    required double torsoCm,
    required String recommendedSize,
    required String calibrationMethod,
  }) async {
    if (userId == null) return false;

    try {
      final url = Uri.parse('$baseUrl/measurements');
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'user_id': userId,
          'shoulder_cm': shoulderCm,
          'hip_cm': hipCm,
          'sleeve_cm': sleeveCm,
          'leg_cm': legCm,
          'torso_cm': torsoCm,
          'recommended_size': recommendedSize,
          'calibration_method': calibrationMethod,
        }),
      );
      return response.statusCode == 200;
    } catch (e) {
      debugPrint('Measurement save error: $e');
      return false;
    }
  }

  /// User ne direct ShopScreen par lai jay che (fresh AI-Fit badges sathe)
  static void goToShop(BuildContext context) {
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (shopContext) => ShopScreen(
          baseUrl: baseUrl,
          userId: userId ?? 1,
          userName: userName,
          gender: gender,
          onOpenScanner: () {
            Navigator.push(
              shopContext, // <-- Navo live context (Camera icon 100% chalse)
              MaterialPageRoute(builder: (_) => const InstructionsScreen()),
            );
          },
        ),
      ),
      (route) => false,
    );
  }

  /// User ne logout kari ne pachu AuthScreen par lai jay che
  static void logout(BuildContext context) {
    userId = null;
    userName = '';
    gender = 'Male';

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (authContext) => AuthScreen(
          baseUrl: baseUrl,
          onAuthSuccess: (id, name, userGender, isNewUser) {
            userId = id;
            userName = name;
            gender = userGender;

            if (isNewUser) {
              Navigator.pushReplacement(
                authContext, // <-- Navo live context (Re-login 100% chalse)
                MaterialPageRoute(builder: (_) => const InstructionsScreen()),
              );
            } else {
              goToShop(authContext);
            }
          },
        ),
      ),
      (route) => false,
    );
  }
}
