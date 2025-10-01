import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../models/result_model.dart';

/// Service per chiamare l'API Selenium invece di eseguire processi locali
/// Funziona su Android, iOS, Web, Desktop
class SeleniumApiService {
  // URL del server API (cambia se il server gira su IP diverso)
  static const String _baseUrl = 'http://192.168.1.11:5001'; // IP Android-visible del Mac
  // Per produzione Synology: 'https://aurora-scraper.synology.me:5001'
  static const Duration _timeout = Duration(seconds: 30);

  /// Scrapa risultati per una categoria specifica chiamando l'API
  static Future<MatchResult?> scrapeCategoryResults(String category) async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 Calling Selenium API for category: $category');
        debugPrint('API URL: $_baseUrl/scrape/$category');
      }

      final uri = Uri.parse('$_baseUrl/scrape/$category');

      final response = await http.get(uri).timeout(_timeout);

      if (kDebugMode) {
        debugPrint('API Response Status: ${response.statusCode}');
        debugPrint('API Response Body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final resultData = data['data'];

          final matchResult = MatchResult(
            id: 'api_${category.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
            homeTeam: resultData['homeTeam'],
            awayTeam: resultData['awayTeam'],
            homeScore: resultData['homeScore'],
            awayScore: resultData['awayScore'],
            matchDate: DateTime.now(),
            category: resultData['category'],
            championship: resultData['championship'],
          );

          if (kDebugMode) {
            debugPrint('✅ API result: ${matchResult.homeTeam} ${matchResult.homeScore}-${matchResult.awayScore} ${matchResult.awayTeam}');
          }

          return matchResult;
        } else {
          if (kDebugMode) {
            debugPrint('❌ API returned no data for $category');
          }
          return null;
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ API request failed with status: ${response.statusCode}');
          debugPrint('Error response: ${response.body}');
        }
        return null;
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling Selenium API: $e');
      }
      return null;
    }
  }

  /// Test se il server API è disponibile
  static Future<bool> isApiAvailable() async {
    try {
      final uri = Uri.parse('$_baseUrl/health');
      final response = await http.get(uri).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['status'] == 'ok';
      }
      return false;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ API server not available: $e');
      }
      return false;
    }
  }

  /// Backward compatibility per Promozione
  static Future<MatchResult?> scrapePromozioneResults() async {
    return scrapeCategoryResults('PROMOZIONE');
  }

  /// Scraping di tutte le categorie tramite API
  static Future<Map<String, MatchResult?>> scrapeAllCategories() async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 Calling Selenium API for all categories');
      }

      final uri = Uri.parse('$_baseUrl/scrape/all');
      final response = await http.get(uri).timeout(const Duration(seconds: 120)); // Timeout più lungo per tutte

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final results = <String, MatchResult?>{};
          final apiData = data['data'] as Map<String, dynamic>;

          for (final entry in apiData.entries) {
            final category = entry.key;
            final categoryData = entry.value;

            if (categoryData != null && categoryData['error'] == null) {
              results[category] = MatchResult(
                id: 'api_${category.toLowerCase()}_${DateTime.now().millisecondsSinceEpoch}',
                homeTeam: categoryData['homeTeam'],
                awayTeam: categoryData['awayTeam'],
                homeScore: categoryData['homeScore'],
                awayScore: categoryData['awayScore'],
                matchDate: DateTime.now(),
                category: categoryData['category'],
                championship: categoryData['championship'],
              );
            } else {
              results[category] = null;
            }
          }

          if (kDebugMode) {
            debugPrint('✅ API returned results for ${results.length} categories');
          }

          return results;
        }
      }

      return {};
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling API for all categories: $e');
      }
      return {};
    }
  }

  /// Mappa le categorie estese di ResultsService ai nomi standard per l'API
  static String? _mapToApiCategory(String category) {
    final cat = category.toUpperCase();

    // Categorie complete di ResultsService -> categorie standard API
    if (cat == 'PROMOZIONE') return 'PROMOZIONE';
    if (cat == 'U21 TERZA' || cat == 'U21') return 'U21';
    if (cat == 'U19 JUNIORES ELITE' || cat == 'U19') return 'U19';
    if (cat == 'U18 ALLIEVI REG' || cat == 'U18') return 'U18';
    if (cat == 'U17 ALLIEVI REG' || cat == 'U17') return 'U17';
    if (cat == 'U16 ALLIEVI' || cat == 'U16') return 'U16';
    if (cat == 'U15 GIOVANISSIMI' || cat == 'U15') return 'U15';
    if (cat == 'U14 GIOVANISSIMI' || cat == 'U14') return 'U14';

    return null; // Categoria non supportata
  }

  /// Wrapper per compatibilità con SeleniumBridge esistente
  static Future<MatchResult?> scrapeCategoryResultsCompatible(String category) async {
    final mappedCategory = _mapToApiCategory(category);
    if (mappedCategory == null) {
      if (kDebugMode) {
        debugPrint('❌ Category not supported by API: $category');
      }
      return null;
    }
    return scrapeCategoryResults(mappedCategory);
  }
}