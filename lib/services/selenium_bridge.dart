import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import '../models/result_model.dart';

/// Bridge per chiamare il scraper Selenium Python dall'app Flutter
class SeleniumBridge {
  static const String _pythonScriptPath = 'selenium_scraper.py';

  /// Ottiene il path assoluto dello script Python
  static String _getScriptPath() {
    // Per Flutter web/desktop, usa il path assoluto del progetto
    return '/Users/vincenzodeluca/sviluppoAPP/claude/aurora_seriate_coaches_app/selenium_scraper.py';
  }

  /// Scrapa risultati per una categoria specifica usando Selenium
  static Future<MatchResult?> scrapeCategoryResults(String category) async {
    // Mappa le categorie estese ai nomi standard
    final mappedCategory = _mapToSeleniumCategory(category);
    if (mappedCategory == null) {
      if (kDebugMode) {
        debugPrint('❌ Category not supported: $category');
      }
      return null;
    }
    try {
      final scriptPath = _getScriptPath();

      if (kDebugMode) {
        debugPrint('🐍 Calling Selenium Python scraper for $mappedCategory...');
        debugPrint('Working directory: ${Directory.current.path}');
        debugPrint('Script absolute path: $scriptPath');
      }

      // Usa i path assoluti per python3 e lo script
      final result = await Process.run(
        '/usr/bin/python3',
        [scriptPath, mappedCategory],
      );

      if (result.exitCode == 0) {
        final stdout = result.stdout as String;

        // Estrai il JSON dal output
        final jsonStart = stdout.indexOf('{');
        final jsonEnd = stdout.lastIndexOf('}') + 1;

        if (jsonStart != -1 && jsonEnd > jsonStart) {
          final jsonString = stdout.substring(jsonStart, jsonEnd);
          final data = json.decode(jsonString);

          final matchResult = MatchResult(
            id: 'selenium_promozione_${DateTime.now().millisecondsSinceEpoch}',
            homeTeam: data['homeTeam'],
            awayTeam: data['awayTeam'],
            homeScore: data['homeScore'],
            awayScore: data['awayScore'],
            matchDate: DateTime.now(),
            category: data['category'],
            championship: data['championship'],
          );

          if (kDebugMode) {
            debugPrint('✅ Selenium result: ${matchResult.homeTeam} ${matchResult.homeScore}-${matchResult.awayScore} ${matchResult.awayTeam}');
          }

          return matchResult;
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ Selenium script failed with exit code: ${result.exitCode}');
          debugPrint('❌ STDERR: ${result.stderr}');
          debugPrint('❌ STDOUT: ${result.stdout}');
        }
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling Selenium: $e');
        if (e is ProcessException) {
          debugPrint('❌ ProcessException details: ${e.message}');
          debugPrint('❌ Executable: ${e.executable}');
          debugPrint('❌ Arguments: ${e.arguments}');
        }
      }
      return null;
    }
  }

  /// Test se Selenium è disponibile
  static Future<bool> isSeleniumAvailable() async {
    try {
      final result = await Process.run('/usr/bin/python3', ['--version']);
      return result.exitCode == 0;
    } catch (e) {
      return false;
    }
  }

  /// Backward compatibility per Promozione
  static Future<MatchResult?> scrapePromozioneResults() async {
    return scrapeCategoryResults('PROMOZIONE');
  }

  /// Mappa le categorie estese di ResultsService ai nomi standard per Selenium
  static String? _mapToSeleniumCategory(String category) {
    final cat = category.toUpperCase();

    // Categorie complete di ResultsService -> categorie standard Selenium
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
}