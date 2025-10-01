import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:html/parser.dart' as html_parser;
import '../models/result_model.dart';

/// Servizio per scraping con WebView per gestire contenuto JavaScript dinamico
class WebViewScraperService {
  static const Duration _pageLoadTimeout = Duration(seconds: 30);
  static const Duration _jsWaitTime = Duration(seconds: 5);

  /// Scrape di una pagina usando WebView per caricare JavaScript
  static Future<List<MatchResult>> scrapeWithWebView(
    String url,
    String category,
  ) async {
    final completer = Completer<List<MatchResult>>();

    try {
      if (kDebugMode) {
        debugPrint('🌐 WebView scraping: $url');
      }

      // Crea WebView controller
      late final WebViewController controller;

      controller = WebViewController()
        ..setJavaScriptMode(JavaScriptMode.unrestricted)
        ..setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1')
        ..setNavigationDelegate(
          NavigationDelegate(
            onPageFinished: (String url) async {
              try {
                if (kDebugMode) {
                  debugPrint('✅ WebView page loaded: $url');
                }

                // Aspetta che JavaScript carichi i contenuti
                await Future.delayed(_jsWaitTime);

                // Ottieni HTML completo dopo JavaScript
                final html = await controller.runJavaScriptReturningResult(
                  'document.documentElement.outerHTML'
                ) as String;

                if (kDebugMode) {
                  debugPrint('📄 HTML ottenuto: ${html.length} caratteri');
                }

                // Parse HTML con dati dinamici
                final results = _parseWebViewHtml(html, category);

                if (!completer.isCompleted) {
                  completer.complete(results);
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('❌ Errore in onPageFinished: $e');
                }
                if (!completer.isCompleted) {
                  completer.complete(<MatchResult>[]);
                }
              }
            },
            onWebResourceError: (WebResourceError error) {
              if (kDebugMode) {
                debugPrint('❌ WebView error: ${error.description}');
              }
              if (!completer.isCompleted) {
                completer.complete(<MatchResult>[]);
              }
            },
          ),
        );

      // Carica la pagina
      await controller.loadRequest(Uri.parse(url));

      // Timeout di sicurezza
      final results = await completer.future.timeout(
        _pageLoadTimeout,
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('⏰ WebView timeout dopo ${_pageLoadTimeout.inSeconds}s');
          }
          return <MatchResult>[];
        },
      );

      return results;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Errore WebView scraping: $e');
      }
      return <MatchResult>[];
    }
  }

  /// Parse HTML ottenuto da WebView (con contenuto JavaScript caricato)
  static List<MatchResult> _parseWebViewHtml(String html, String category) {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Parsing WebView HTML per categoria: $category');
      }

      // Rimuovi le virgolette extra che JavaScript potrebbe aggiungere
      final cleanHtml = html.replaceAll(r'\"', '"').replaceAll(r"\'", "'");

      final document = html_parser.parse(cleanHtml);
      final bodyText = document.body?.text ?? '';

      if (kDebugMode) {
        debugPrint('📝 Body text: ${bodyText.length} caratteri');
        debugPrint('🔍 Aurora presente: ${bodyText.toLowerCase().contains('aurora')}');
      }

      // Cerca pattern di risultati nel testo completo
      return _extractResultsFromText(bodyText, category);

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Errore parsing WebView HTML: $e');
      }
      return <MatchResult>[];
    }
  }

  /// Estrae risultati dal testo usando pattern regex avanzati
  static List<MatchResult> _extractResultsFromText(String text, String category) {
    final List<MatchResult> results = [];

    try {
      if (kDebugMode) {
        // Debug: mostra contesto Aurora
        final auroraMatches = RegExp(r'aurora[^\n]{0,200}', caseSensitive: false).allMatches(text);
        debugPrint('🔍 Contesti Aurora trovati: ${auroraMatches.length}');
        for (int i = 0; i < auroraMatches.length && i < 3; i++) {
          final match = auroraMatches.elementAt(i);
          debugPrint('  Context $i: "${match.group(0)}"');
        }

        // Debug: cerca punteggi generici
        final scoreMatches = RegExp(r'(\d+)\s*[-–—:]\s*(\d+)').allMatches(text);
        debugPrint('🔍 Pattern punteggio trovati: ${scoreMatches.length}');
        for (int i = 0; i < scoreMatches.length && i < 5; i++) {
          final match = scoreMatches.elementAt(i);
          final start = (match.start - 50).clamp(0, text.length);
          final end = (match.end + 50).clamp(0, text.length);
          final context = text.substring(start, end).replaceAll('\n', ' ').replaceAll('\t', ' ');
          debugPrint('  Score $i: "${match.group(0)}" in "$context"');
        }
      }

      // Pattern per Aurora Seriate vs altre squadre - MIGLIORATI
      final patterns = [
        // Pattern base "Aurora Seriate" con varianti nome
        RegExp(r'aurora\s*seriate\s*(?:1967)?[^\d]{0,50}(\d+)\s*[-–—:]\s*(\d+)[^\d]{0,50}([a-z\s]{3,30})', caseSensitive: false),
        // Pattern inverso squadra avversaria prima
        RegExp(r'([a-z\s]{3,30})[^\d]{0,50}(\d+)\s*[-–—:]\s*(\d+)[^\d]{0,50}aurora\s*seriate', caseSensitive: false),
        // Pattern più permissivo per contenuto dinamico
        RegExp(r'aurora[^0-9]{0,100}(\d+)\s*[-–—:]\s*(\d+)', caseSensitive: false),
        RegExp(r'(\d+)\s*[-–—:]\s*(\d+)[^0-9]{0,100}aurora', caseSensitive: false),
        // Pattern con separatori diversi
        RegExp(r'aurora\s+seriate.*?(\d+)\s+(\d+)', caseSensitive: false),
        RegExp(r'(\d+)\s+(\d+).*?aurora\s+seriate', caseSensitive: false),
      ];

      for (int p = 0; p < patterns.length; p++) {
        final pattern = patterns[p];
        final matches = pattern.allMatches(text);

        for (final match in matches) {
          try {
            String? homeTeam, awayTeam;
            int? homeScore, awayScore;

            if (p == 0) {
              // Aurora è casa
              homeTeam = 'Aurora Seriate 1967';
              homeScore = int.tryParse(match.group(1) ?? '');
              awayScore = int.tryParse(match.group(2) ?? '');
              awayTeam = _cleanTeamName(match.group(3) ?? '');
            } else if (p == 1) {
              // Aurora è ospite
              homeTeam = _cleanTeamName(match.group(1) ?? '');
              homeScore = int.tryParse(match.group(2) ?? '');
              awayScore = int.tryParse(match.group(3) ?? '');
              awayTeam = 'Aurora Seriate 1967';
            } else if (p == 2) {
              // Aurora è casa (pattern 3)
              homeTeam = 'Aurora Seriate 1967';
              homeScore = int.tryParse(match.group(1) ?? '');
              awayScore = int.tryParse(match.group(2) ?? '');
              awayTeam = _cleanTeamName(match.group(3) ?? '');
            } else if (p == 3) {
              // Aurora è ospite (pattern 4)
              homeTeam = _cleanTeamName(match.group(1) ?? '');
              homeScore = int.tryParse(match.group(2) ?? '');
              awayScore = int.tryParse(match.group(3) ?? '');
              awayTeam = 'Aurora Seriate 1967';
            }

            // Validazione
            if (homeTeam != null && awayTeam != null &&
                homeScore != null && awayScore != null &&
                homeTeam.isNotEmpty && awayTeam.isNotEmpty &&
                homeScore >= 0 && awayScore >= 0 &&
                homeScore <= 50 && awayScore <= 50) {

              // Evita duplicati
              final exists = results.any((r) =>
                  r.homeTeam.toLowerCase() == homeTeam!.toLowerCase() &&
                  r.awayTeam.toLowerCase() == awayTeam!.toLowerCase());

              if (!exists) {
                final result = MatchResult(
                  id: '${category}_${homeTeam}_${awayTeam}_${DateTime.now().millisecondsSinceEpoch}',
                  homeTeam: homeTeam,
                  awayTeam: awayTeam,
                  homeScore: homeScore,
                  awayScore: awayScore,
                  matchDate: DateTime.now(),
                  category: category,
                  championship: _getChampionshipName(category),
                );

                results.add(result);

                if (kDebugMode) {
                  debugPrint('✅ Match trovato: $homeTeam $homeScore-$awayScore $awayTeam');
                }
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('❌ Errore parsing match: $e');
            }
          }
        }
      }

      if (kDebugMode) {
        debugPrint('🎯 Risultati WebView estratti: ${results.length}');
      }

      return results;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Errore estrazione risultati: $e');
      }
      return <MatchResult>[];
    }
  }

  /// Pulisce il nome della squadra
  static String _cleanTeamName(String name) {
    return name
        .trim()
        .replaceAll(RegExp(r'\s+'), ' ')
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .trim()
        .split(' ')
        .take(4) // Max 4 parole
        .join(' ');
  }

  /// Ottieni il nome completo del campionato
  static String _getChampionshipName(String category) {
    switch (category) {
      case 'Promozione':
        return 'Promozione Girone A';
      case 'U21':
        return 'Under21 Girone D';
      case 'U19':
        return 'Juniores Elite U19 Girone C';
      case 'U18':
        return 'Allievi Regionali U18 Girone D';
      case 'U17':
        return 'Allievi Regionali U17 Girone D';
      case 'U16':
        return 'Allievi Provinciali U16 Girone D Bergamo';
      case 'U15':
        return 'Giovanissimi Provinciali U15 Girone C Bergamo';
      case 'U14':
        return 'Giovanissimi Provinciali U14 Girone C Bergamo';
      default:
        return 'Campionato $category';
    }
  }

  /// Widget WebView nascosta per scraping
  static Widget createHiddenWebView({
    required String url,
    required String category,
    required Function(List<MatchResult>) onResults,
  }) {
    late final WebViewController controller;

    controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setUserAgent('Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1')
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (String loadedUrl) async {
            try {
              await Future.delayed(_jsWaitTime);

              final html = await controller.runJavaScriptReturningResult(
                'document.documentElement.outerHTML'
              ) as String;

              final results = _parseWebViewHtml(html, category);
              onResults(results);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Errore WebView widget: $e');
              }
              onResults(<MatchResult>[]);
            }
          },
        ),
      )
      ..loadRequest(Uri.parse(url));

    return SizedBox(
      width: 1,
      height: 1,
      child: WebViewWidget(controller: controller),
    );
  }
}