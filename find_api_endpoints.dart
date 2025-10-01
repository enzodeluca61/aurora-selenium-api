import 'dart:io';
import 'package:http/http.dart' as http;

/// Cerca gli endpoint API che tuttocampo.it usa per caricare i risultati
void main() async {
  print('=== RICERCA API ENDPOINTS ===');

  final headers = {
    'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
    'Accept': 'application/json, text/plain, */*',
    'Accept-Language': 'it-IT,it;q=0.9,en;q=0.8',
    'Accept-Encoding': 'gzip, deflate, br',
    'DNT': '1',
    'Connection': 'keep-alive',
    'Referer': 'https://www.tuttocampo.it/Lombardia/AllieviRegionaliU17/GironeD/Risultati',
  };

  // Possibili endpoint API basati su pattern comuni
  final possibleEndpoints = [
    'https://www.tuttocampo.it/api/risultati/AllieviRegionaliU17/GironeD',
    'https://www.tuttocampo.it/api/matches/AllieviRegionaliU17/GironeD',
    'https://www.tuttocampo.it/api/girone/AllieviRegionaliU17/GironeD/risultati',
    'https://api.tuttocampo.it/risultati/AllieviRegionaliU17/GironeD',
    'https://api.tuttocampo.it/matches/AllieviRegionaliU17/GironeD',
    'https://www.tuttocampo.it/Lombardia/AllieviRegionaliU17/GironeD/Risultati/json',
    'https://www.tuttocampo.it/Lombardia/AllieviRegionaliU17/GironeD/Risultati/data',
    'https://www.tuttocampo.it/api/Lombardia/AllieviRegionaliU17/GironeD/Risultati',
  ];

  print('Test di ${possibleEndpoints.length} possibili endpoint...\n');

  for (int i = 0; i < possibleEndpoints.length; i++) {
    final endpoint = possibleEndpoints[i];
    print('${i + 1}. Testing: $endpoint');

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: headers,
      ).timeout(Duration(seconds: 10));

      print('   Status: ${response.statusCode}');

      if (response.statusCode == 200) {
        final body = response.body;
        print('   ✅ SUCCESSO! Lunghezza: ${body.length}');

        // Controlla se contiene dati utili
        final lowerBody = body.toLowerCase();
        final hasAurora = lowerBody.contains('aurora');
        final hasJson = body.trim().startsWith('{') || body.trim().startsWith('[');
        final hasScore = RegExp(r'\d+\s*[-–—]\s*\d+').hasMatch(body);

        print('   Aurora presente: $hasAurora');
        print('   Formato JSON: $hasJson');
        print('   Pattern punteggio: $hasScore');

        if (hasAurora || hasJson || hasScore) {
          print('   *** ENDPOINT PROMETTENTE! ***');
          print('   Preview: ${body.length > 300 ? body.substring(0, 300) : body}...');
        }

      } else if (response.statusCode == 404) {
        print('   ❌ Not Found');
      } else if (response.statusCode == 403) {
        print('   ❌ Forbidden');
      } else {
        print('   ❌ Error: ${response.statusCode}');
      }

    } catch (e) {
      print('   ❌ Exception: $e');
    }

    print('');

    // Pausa per evitare rate limiting
    if (i < possibleEndpoints.length - 1) {
      await Future.delayed(Duration(milliseconds: 1500));
    }
  }

  // Test di endpoint generici
  print('\n=== TEST ENDPOINT GENERICI ===');
  final genericEndpoints = [
    'https://www.tuttocampo.it/api',
    'https://api.tuttocampo.it',
    'https://www.tuttocampo.it/api/squadre/Aurora',
    'https://www.tuttocampo.it/api/search?q=Aurora',
  ];

  for (final endpoint in genericEndpoints) {
    print('Testing: $endpoint');

    try {
      final response = await http.get(
        Uri.parse(endpoint),
        headers: headers,
      ).timeout(Duration(seconds: 8));

      print('  Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        final preview = response.body.length > 200 ? response.body.substring(0, 200) : response.body;
        print('  Body: $preview...');
      }

    } catch (e) {
      print('  Error: $e');
    }

    await Future.delayed(Duration(milliseconds: 1000));
  }

  print('\n=== ANALISI COMPLETATA ===');
  print('Se nessun endpoint è stato trovato, tuttocampo.it probabilmente:');
  print('1. Usa endpoint dinamici con token/session');
  print('2. Carica dati via WebSocket');
  print('3. Usa autenticazione complessa');
  print('4. Ha endpoint con nomi non standard');
  print('\nSoluzione: Implementare WebView o browser headless per JavaScript');

  exit(0);
}