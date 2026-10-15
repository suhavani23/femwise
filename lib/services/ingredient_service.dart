import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'account_service.dart';
import 'api_config.dart';

class IngredientService {
  IngredientService(
      {http.Client? client,
      Future<Map<String, String>> Function(bool refresh)? authorization})
      : _client = client,
        _authorization = authorization ??
            ((refresh) => AccountService.instance
                .foodAuthorizationHeaders(refresh: refresh));

  final http.Client? _client;
  final Future<Map<String, String>> Function(bool refresh) _authorization;

  Future<String> analyze(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || trimmed.length > 20000) {
      throw const AccountException(
          'Enter between 1 and 20,000 characters of ingredient text.');
    }
    final client = _client ?? http.Client();
    try {
      for (var attempt = 0; attempt < 2; attempt++) {
        final response = await client
            .post(
              ApiConfig.endpoint(
                  ApiConfig.packagedFood, '/extract_ingredients'),
              headers: {
                ...await _authorization(attempt > 0),
                'Content-Type': 'application/json; charset=UTF-8'
              },
              body: jsonEncode({'text': trimmed}),
            )
            .timeout(const Duration(seconds: 90));
        if (response.statusCode == 401 && attempt == 0) continue;
        dynamic data;
        try {
          data = jsonDecode(response.body);
        } on FormatException {
          data = null;
        }
        if (response.statusCode == 200 && data is Map<String, dynamic>) {
          return formatIngredientReview(data);
        }
        if (response.statusCode == 404) {
          throw const AccountException(
              'Ingredient analysis is being updated. Please try again later.');
        }
        if (response.statusCode == 429) {
          throw const AccountException(
              'Too many scans. Please wait a few minutes and try again.');
        }
        final detail = data is Map ? data['detail'] : null;
        throw AccountException(detail is String
            ? detail
            : 'Ingredient analysis is unavailable. Please try again.');
      }
      throw const AccountException(
          'Unable to start a scan session. Please retry.');
    } on TimeoutException {
      throw const AccountException(
          'The server took too long. Please try again.');
    } on http.ClientException {
      throw const AccountException(
          'Unable to connect. Check your internet connection and retry.');
    } finally {
      if (_client == null) client.close();
    }
  }
}

String formatIngredientReview(Map<String, dynamic> data) {
  final ingredients = data['ingredients'];
  if (ingredients is! List ||
      ingredients.isEmpty ||
      data['summary'] is! String) {
    throw const AccountException(
        'The review was incomplete. Please try again.');
  }
  final output = StringBuffer(
      'AI ingredient review\n\n${data['summary']}\n\nIngredients\n');
  for (final item in ingredients) {
    if (item is! Map || item['name'] is! String || item['note'] is! String) {
      throw const AccountException(
          'The review was incomplete. Please try again.');
    }
    final category =
        (item['category'] as String? ?? 'uncertain').replaceAll('_', ' ');
    output.writeln('• ${item['name']} ($category)\n  ${item['note']}\n');
  }
  final limitations = data['limitations'];
  if (limitations is List && limitations.isNotEmpty) {
    output.writeln('Limitations');
    for (final note in limitations) {
      output.writeln('• $note');
    }
    output.writeln();
  }
  output.write(data['disclaimer'] as String? ??
      'AI-generated review, not medical advice. Check the original label.');
  return output.toString();
}
