import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:html/parser.dart' as html_parser;
import 'package:html/dom.dart';
import 'package:intl/intl.dart';
import '../models/result_model.dart';
import 'webview_scraper_service.dart';

class TuttocampoScraper {
  static const String _baseUrl = 'https://www.tuttocampo.it';

  // ENHANCED SAFETY: Aggressive timeouts and limits to prevent crashes
  static const Duration _httpTimeout = Duration(seconds: 15); // Increased for better reliability
  static const Duration _totalOperationTimeout = Duration(seconds: 45); // Max time per scraping operation
  static const int _maxElementsToProcess = 100; // Increased for better results
  static const Duration _delayBetweenRequests = Duration(seconds: 2); // Anti-rate-limiting

  // URL per i gironi Aurora Seriate - COPERTURA ASSOLUTA SETTORE GIOVANILE + PRIMA SQUADRA
  static const Map<String, String> _auroraUrls = {
    'Promozione': '/Lombardia/Promozione/GironeA/Risultati',
    'U21': '/Lombardia/Under21/GironeD/Risultati',
    'U19': '/Lombardia/JunioresEliteU19/GironeC/Risultati',
    'U18': '/Lombardia/AllieviRegionaliU18/GironeD/Risultati',
    'U17': '/Lombardia/AllieviRegionaliU17/GironeD/Risultati',
    'U16': '/Lombardia/AllieviProvincialiU16/GironeDBergamo/Risultati',
    'U15': '/Lombardia/GiovanissimiProvincialiU15/GironeCBergamo/Risultati',
    'U14': '/Lombardia/GiovanissimiProvincialiU14/GironeCBergamo/Risultati',
  };

  // URL alternativi da provare quando i primi falliscono
  static const Map<String, List<String>> _alternativeUrls = {
    'U19': [
      '/Lombardia/JunioresEliteU19/GironeC/Partita/3.2/aurora-seriate-1967-citt-di-albino',
      '/Lombardia/JunioresEliteU19/GironeC',
      '/Lombardia/JunioresEliteU19/GironeC/Classifica',
    ],
    'U19 JUNIORES ELITE': [
      '/Lombardia/JunioresEliteU19/GironeC/Partita/3.2/aurora-seriate-1967-citt-di-albino',
      '/Lombardia/JunioresEliteU19/GironeC',
      '/Lombardia/JunioresEliteU19/GironeC/Classifica',
    ],
    'U21': [
      '/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit',
      '/Lombardia/Under21/GironeD/Classifica',
      '/Lombardia/Under21/GironeD',
      '/Lombardia/Under21/GironeD/Calendario',
    ],
    'U21 TERZA': [
      '/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit',
      '/Lombardia/Under21/GironeD/Classifica',
      '/Lombardia/Under21/GironeD',
      '/Lombardia/Under21/GironeD/Calendario',
    ],
    'U18': [
      '/Lombardia/AllieviRegionaliU18/GironeD/Classifica',
      '/Lombardia/AllieviRegionaliU18/GironeD',
    ],
    'U18 ALLIEVI REG': [
      '/Lombardia/AllieviRegionaliU18/GironeD/Classifica',
      '/Lombardia/AllieviRegionaliU18/GironeD',
    ],
  };

  // Headers dinamici per evitare il rilevamento come bot
  static Map<String, String> get _headers => _getRandomHeaders();

  static final List<Map<String, String>> _headerVariants = [
    {
      'User-Agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'it-IT,it;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate, br',
      'DNT': '1',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Cache-Control': 'max-age=0',
      'Referer': 'https://www.tuttocampo.it/',
    },
    {
      'User-Agent': 'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8',
      'Accept-Language': 'it-IT,it;q=0.9,en-US;q=0.8,en;q=0.7',
      'Accept-Encoding': 'gzip, deflate, br',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Sec-Fetch-Dest': 'document',
      'Sec-Fetch-Mode': 'navigate',
      'Sec-Fetch-Site': 'none',
      'Sec-Fetch-User': '?1',
      'Referer': 'https://google.com/',
    },
    {
      'User-Agent': 'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/121.0.0.0 Safari/537.36',
      'Accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'Accept-Language': 'it,en-US;q=0.9,en;q=0.8',
      'Accept-Encoding': 'gzip, deflate',
      'Connection': 'keep-alive',
      'Upgrade-Insecure-Requests': '1',
      'Cache-Control': 'no-cache',
      'Pragma': 'no-cache',
      'Referer': 'https://www.tuttocampo.it/Lombardia/',
    },
  ];

  static Map<String, String> _getRandomHeaders() {
    final random = DateTime.now().millisecondsSinceEpoch % _headerVariants.length;
    return _headerVariants[random];
  }

  /// Scrape dei risultati per tutte le categorie Aurora Seriate
  static Future<List<MatchResult>> scrapeAllAuroraResults() async {
    final List<MatchResult> allResults = [];

    for (final entry in _auroraUrls.entries) {
      try {
        final categoryResults = await _scrapeCategory(entry.key, entry.value);
        allResults.addAll(categoryResults);

        if (kDebugMode) {
          debugPrint('Scraped ${categoryResults.length} results for ${entry.key}');
        }

        // Pausa intelligente tra le richieste per evitare rate limiting
        await Future.delayed(_delayBetweenRequests);
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error scraping ${entry.key}: $e');
        }
      }
    }

    // Ordina per data
    allResults.sort((a, b) => b.matchDate.compareTo(a.matchDate));

    if (kDebugMode) {
      debugPrint('Total scraped results: ${allResults.length}');
    }

    return allResults;
  }

  /// Scrape pubblico per una singola categoria (usato dal ResultsService)
  static Future<List<MatchResult>> scrapeCategoryResults(String category, String urlPath) async {
    // ENHANCED SAFETY: Global timeout for entire scraping operation
    try {
      return await _scrapeCategory(category, urlPath).timeout(
        _totalOperationTimeout,
        onTimeout: () {
          if (kDebugMode) {
            debugPrint('TIMEOUT: Scraping operation for $category exceeded ${_totalOperationTimeout.inSeconds}s');
          }
          return <MatchResult>[]; // Return empty list on timeout
        },
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('ERROR in scrapeCategory for $category: $e');
      }
      return <MatchResult>[];
    }
  }

  /// Scrape specifico per una partita (ricerca più mirata)
  static Future<MatchResult?> scrapeSpecificMatch({
    required String category,
    required String homeTeam,
    required String awayTeam,
    required String urlPath,
  }) async {
    try {
      if (kDebugMode) {
        debugPrint('🎯 Scraping specific match: $homeTeam vs $awayTeam ($category)');
      }

      // Usa il normale scraping di categoria ma filtra per la partita specifica
      final allResults = await _scrapeCategory(category, urlPath);

      // Cerca la partita specifica nei risultati
      for (final result in allResults) {
        if (_isMatchingTeams(result, homeTeam, awayTeam)) {
          if (kDebugMode) {
            debugPrint('✅ Found specific match: ${result.homeTeam} ${result.homeScore}-${result.awayScore} ${result.awayTeam}');
          }
          return result;
        }
      }

      if (kDebugMode) {
        debugPrint('❌ Specific match not found in ${allResults.length} scraped results');
      }
      return null;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error scraping specific match: $e');
      }
      return null;
    }
  }

  /// Verifica se un risultato corrisponde alle squadre cercate
  static bool _isMatchingTeams(MatchResult result, String homeTeam, String awayTeam) {
    final resultHome = result.homeTeam.toLowerCase().trim();
    final resultAway = result.awayTeam.toLowerCase().trim();
    final targetHome = homeTeam.toLowerCase().trim();
    final targetAway = awayTeam.toLowerCase().trim();

    // Verifica match diretto
    if (resultHome.contains(targetHome.replaceAll('aurora seriate', 'aurora')) &&
        resultAway.contains(targetAway)) {
      return true;
    }

    // Verifica match inverso (case insensitive)
    if (resultHome.contains(targetAway) &&
        resultAway.contains(targetHome.replaceAll('aurora seriate', 'aurora'))) {
      return true;
    }

    // Verifica con "aurora" semplificato
    if ((targetHome.contains('aurora') || targetAway.contains('aurora')) &&
        (resultHome.contains('aurora') || resultAway.contains('aurora'))) {

      // Verifica che anche l'altra squadra matchi parzialmente
      final otherTarget = targetHome.contains('aurora') ? targetAway : targetHome;
      final otherResult = resultHome.contains('aurora') ? resultAway : resultHome;

      return otherResult.contains(otherTarget) || otherTarget.contains(otherResult);
    }

    return false;
  }

  /// Scrape dei risultati per una singola categoria con retry logic e WebView fallback
  static Future<List<MatchResult>> _scrapeCategory(String category, String urlPath) async {
    final url = '$_baseUrl$urlPath';
    const maxRetries = 3;

    for (int attempt = 1; attempt <= maxRetries; attempt++) {
      try {
        if (kDebugMode) {
          debugPrint('Scraping $category from: $url (attempt $attempt/$maxRetries)');
        }

        // Aggiungi delay progressivo tra tentativi per evitare rate limiting
        if (attempt > 1) {
          final delaySeconds = attempt * 3; // Progressivo: 3s, 6s, 9s...
          if (kDebugMode) {
            debugPrint('Waiting $delaySeconds seconds before retry $attempt...');
          }
          await Future.delayed(Duration(seconds: delaySeconds));
        }

        final response = await http.get(
          Uri.parse(url),
          headers: _headers,
        ).timeout(_httpTimeout);

        if (response.statusCode == 200) {
          final document = html_parser.parse(response.body);
          final bodyText = document.body?.text ?? '';

          // Controlla se la pagina ha contenuto dinamico
          final hasLoadingElement = document.querySelector('.loading-preview') != null;
          final hasMatchDetails = document.querySelector('#match_details') != null;
          final hasAurora = bodyText.toLowerCase().contains('aurora');
          final hasTables = document.querySelectorAll('table').isNotEmpty;

          if (kDebugMode) {
            debugPrint('Page analysis: Aurora=$hasAurora, Tables=$hasTables, Loading=$hasLoadingElement');
          }

          // Prova parsing tradizionale
          final traditionalResults = _parseResultsFromDocument(document, category);

          if (traditionalResults.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('✅ Traditional parsing successful: ${traditionalResults.length} results');
            }
            return traditionalResults;
          }

          // Se Aurora è presente ma non abbiamo risultati, probabilmente è contenuto dinamico
          if (hasAurora && traditionalResults.isEmpty) {
            if (kDebugMode) {
              debugPrint('🔄 Aurora found but no results - trying WebView scraping...');
            }

            // Prova WebView per contenuto dinamico (solo su mobile)
            try {
              if (kIsWeb) {
                if (kDebugMode) {
                  debugPrint('🌐 Running on web - trying enhanced text parsing instead of WebView');
                }
                // Su web, prova parsing avanzato del testo esistente
                final enhancedResults = _tryAdvancedTextParsing(bodyText, category);
                if (enhancedResults.isNotEmpty) {
                  if (kDebugMode) {
                    debugPrint('✅ Enhanced text parsing successful: ${enhancedResults.length} results');
                  }
                  return enhancedResults;
                }
              } else {
                // Su mobile, usa WebView
                final webViewResults = await WebViewScraperService.scrapeWithWebView(url, category);
                if (webViewResults.isNotEmpty) {
                  if (kDebugMode) {
                    debugPrint('✅ WebView scraping successful: ${webViewResults.length} results');
                  }
                  return webViewResults;
                }
              }
            } catch (e) {
              if (kDebugMode) {
                debugPrint('❌ Dynamic content scraping failed: $e');
              }
            }
          }

          if (kDebugMode) {
            debugPrint('No results found for $category');
          }
          return traditionalResults;
        } else if (response.statusCode == 403) {
          if (kDebugMode) {
            debugPrint('=== HTTP 403 ACCESS DENIED ===');
            debugPrint('Category: $category');
            debugPrint('URL: $url');
            debugPrint('Attempt: $attempt/$maxRetries');
            debugPrint('Tuttocampo.it is blocking our requests');
          }

          // Per errore 403, prova prima con headers diversi
          if (attempt == 1) {
            _rotateHeaders();
            await Future.delayed(const Duration(seconds: 2));
            continue;
          }

          // Al secondo tentativo, prova URL alternativi se disponibili
          if (attempt == 2 && _alternativeUrls.containsKey(category)) {
            final alternativeUrls = _alternativeUrls[category]!;

            if (kDebugMode) {
              debugPrint('=== TRYING ALTERNATIVE URLS FOR $category ===');
              debugPrint('Found ${alternativeUrls.length} alternative URLs to test');
            }

            for (int i = 0; i < alternativeUrls.length; i++) {
              final altUrl = alternativeUrls[i];
              try {
                if (kDebugMode) {
                  debugPrint('Alternative URL ${i + 1}/${alternativeUrls.length} for $category: $_baseUrl$altUrl');
                }

                final altResponse = await http.get(
                  Uri.parse('$_baseUrl$altUrl'),
                  headers: _headers,
                ).timeout(_httpTimeout);

                if (altResponse.statusCode == 200) {
                  final document = html_parser.parse(altResponse.body);
                  final results = _parseResultsFromDocument(document, category);

                  if (kDebugMode) {
                    debugPrint('✅ Alternative URL SUCCESS for $category: ${results.length} results from $_baseUrl$altUrl');
                  }

                  return results;
                } else {
                  if (kDebugMode) {
                    debugPrint('❌ Alternative URL failed for $category: HTTP ${altResponse.statusCode}');
                  }
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('❌ Error with alternative URL for $category: $e');
                }
              }

              // Piccola pausa tra URL alternativi
              if (i < alternativeUrls.length - 1) {
                await Future.delayed(const Duration(milliseconds: 500));
              }
            }

            if (kDebugMode) {
              debugPrint('=== ALL ALTERNATIVE URLS FAILED FOR $category ===');
            }
          }

          // Se continua a dare 403 e gli URL alternativi falliscono
          if (kDebugMode) {
            debugPrint('FINAL RESULT: Tuttocampo.it access blocked - returning empty results');
            debugPrint('This is why you see 0-0 scores - no data can be retrieved');
            debugPrint('============================');
          }
          return [];
        } else if (response.statusCode == 405) {
          if (kDebugMode) {
            debugPrint('HTTP 405 - Method not allowed for $category. URL might be invalid or changed.');
          }

          // Per errore 405, non ritentare - è un problema di URL/metodo
          if (category == 'U14') {
            // Prova URL alternativi per U14
            final alternativeUrls = [
              '/Lombardia/GiovanissimiFigc/GironeCBergamo/Risultati',
              '/Lombardia/GiovanissimiScolastici/GironeCBergamo/Risultati',
              '/Lombardia/Esordienti/GironeCBergamo/Risultati',
            ];

            for (final altUrl in alternativeUrls) {
              try {
                if (kDebugMode) {
                  debugPrint('Trying alternative URL for U14: $altUrl');
                }

                final altResponse = await http.get(
                  Uri.parse('$_baseUrl$altUrl'),
                  headers: _headers,
                ).timeout(_httpTimeout);

                if (altResponse.statusCode == 200) {
                  final document = html_parser.parse(altResponse.body);
                  final results = _parseResultsFromDocument(document, category);

                  if (kDebugMode) {
                    debugPrint('Alternative URL worked for U14: ${results.length} results');
                  }

                  return results;
                }
              } catch (e) {
                if (kDebugMode) {
                  debugPrint('Alternative URL failed: $e');
                }
              }
            }
          }

          // Se nessun URL alternativo funziona, restituisci lista vuota invece di errore
          if (kDebugMode) {
            debugPrint('Skipping category $category due to HTTP 405 error');
          }
          return [];
        } else {
          throw Exception('HTTP ${response.statusCode}: Tuttocampo.it temporaneamente non accessibile');
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error scraping $category (attempt $attempt): $e');

          // Diagnosi specifiche degli errori
          if (e.toString().contains('Failed host lookup')) {
            debugPrint('Network error: DNS resolution failed - check internet connection');
          } else if (e.toString().contains('SocketException')) {
            debugPrint('Network error: Connection failed - server might be down');
          } else if (e.toString().contains('TimeoutException')) {
            debugPrint('Network error: Request timeout - server slow or overloaded');
          } else if (e.toString().contains('403')) {
            debugPrint('Access denied: Server blocking requests - trying different approach');
          } else {
            debugPrint('Unexpected error: $e');
          }
        }

        // Non fallire immediatamente su errori di rete - riprova
        if (attempt == maxRetries) {
          if (kDebugMode) {
            debugPrint('All retry attempts failed for $category, returning empty results');
          }
          return [];
        }
      }
    }

    return [];
  }

  /// Ruota gli headers per evitare il rilevamento
  static void _rotateHeaders() {
    // Alternate between different User-Agent strings
    final userAgents = [
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_1 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.1 Mobile/15E148 Safari/604.1',
      'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64; rv:109.0) Gecko/20100101 Firefox/119.0',
      'Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/119.0.0.0 Safari/537.36',
    ];

    _headers['User-Agent'] = userAgents[DateTime.now().millisecond % userAgents.length];
  }

  /// Parse dei risultati dal documento HTML con approccio multi-strategia e limitazioni di sicurezza
  static List<MatchResult> _parseResultsFromDocument(Document document, String category, {bool isDynamic = false}) {
    final List<MatchResult> results = [];
    int elementsProcessed = 0;

    if (kDebugMode) {
      debugPrint('Parsing document for category: $category');
      debugPrint('Document title: ${document.querySelector('title')?.text}');
      debugPrint('SAFETY: Max elements to process: $_maxElementsToProcess');
    }

    try {
      // Strategia 0: Rileva se è una pagina di singola partita (nuovo URL format)
      final pageTitle = document.querySelector('title')?.text ?? '';
      final pageUrl = document.querySelector('link[rel="canonical"]')?.attributes['href'] ?? '';
      final pageContent = document.body?.text ?? '';

      if (pageTitle.toLowerCase().contains('partita') ||
          pageUrl.contains('/Partita/') ||
          pageContent.contains('aurora-seriate') ||
          pageContent.contains('Aurora Seriate')) {

        if (kDebugMode) {
          debugPrint('=== DETECTED SINGLE MATCH PAGE ===');
          debugPrint('Page title: $pageTitle');
          debugPrint('Page URL: $pageUrl');
          debugPrint('Trying single match parsing...');
        }

        final singleMatchResults = _parseSingleMatchPage(document, category);
        if (singleMatchResults.isNotEmpty) {
          results.addAll(singleMatchResults);
          if (kDebugMode) {
            debugPrint('✅ SUCCESS: Found ${results.length} results from single match page');
          }
          // Ritorna subito se trova risultati nella pagina singola
          return singleMatchResults;
        } else {
          if (kDebugMode) {
            debugPrint('❌ Single match parsing failed, trying standard parsing...');
          }
        }
      }

      // Strategia 1: Tabelle dei risultati (formato tuttocampo specifico) - CON LIMITI
      final tables = document.querySelectorAll('table.tc-table.table-results, table.table-results, .tc-table, table, .table, .risultati-table, .matches-table, .calendar-table, .calendar-container table, .matches-container table, .risultati-container table, [class*="table"], [class*="calendar"], [class*="result"]');
      for (final table in tables) {
        if (elementsProcessed >= _maxElementsToProcess) {
          if (kDebugMode) {
            debugPrint('SAFETY BREAK: Reached max elements limit in tables processing');
          }
          break;
        }
        final tableResults = _parseResultsFromTable(table, category);
        results.addAll(tableResults);
        elementsProcessed++;
      }

      if (kDebugMode) {
        debugPrint('Found ${results.length} results from tables');
      }

      // Strategia 2: Div contenitori delle partite (migliorata per tuttocampo) - CON LIMITI
      if (results.isEmpty && elementsProcessed < _maxElementsToProcess) {
        final resultContainers = document.querySelectorAll(
          '.match, .partita, .risultato, .fixture, .game, .match-result, .calendar-item, .event, '
          '.match-row, .calendario-row, .calendar-row, .game-row, .result-row, '
          '[class*="match"], [class*="partita"], [class*="result"], [class*="game"], [class*="calendar"], '
          '.grid-item, .table-row, .competition-match, .giornata-match'
        );
        for (final container in resultContainers) {
          if (elementsProcessed >= _maxElementsToProcess) {
            if (kDebugMode) {
              debugPrint('SAFETY BREAK: Reached max elements limit in containers processing');
            }
            break;
          }
          try {
            final result = _parseResultFromContainer(container, category);
            if (result != null) {
              results.add(result);
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error parsing container: $e');
            }
          }
          elementsProcessed++;
        }

        if (kDebugMode) {
          debugPrint('Found ${results.length} results from containers');
        }
      }

      // Strategia 3: Lista elementi e nuovi pattern tuttocampo - CON LIMITI
      if (results.isEmpty && elementsProcessed < _maxElementsToProcess) {
        final listItems = document.querySelectorAll(
          'li, .item, .row, tr, .table-cell, .grid-cell, '
          '[data-match], [data-result], [data-game], '
          '.score-container, .match-container, .result-container'
        );
        for (final item in listItems) {
          if (elementsProcessed >= _maxElementsToProcess) {
            if (kDebugMode) {
              debugPrint('SAFETY BREAK: Reached max elements limit in list items processing');
            }
            break;
          }
          try {
            final result = _parseResultFromListItem(item, category);
            if (result != null) {
              results.add(result);
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error parsing list item: $e');
            }
          }
          elementsProcessed++;
        }

        if (kDebugMode) {
          debugPrint('Found ${results.length} results from list items');
        }
      }

      // Strategia 4: Ricerca avanzata per elementi con attributi data o ID specifici - CON LIMITI
      if (results.isEmpty && elementsProcessed < _maxElementsToProcess) {
        final advancedElements = document.querySelectorAll(
          '[id*="match"], [id*="result"], [id*="game"], [id*="partita"], '
          '[class*="match-"], [class*="result-"], [class*="game-"], '
          'span, div, td'
        );

        for (final element in advancedElements) {
          if (elementsProcessed >= _maxElementsToProcess) {
            if (kDebugMode) {
              debugPrint('SAFETY BREAK: Reached max elements limit in advanced search');
            }
            break;
          }
          try {
            if (element.text.toLowerCase().contains('aurora')) {
              final result = _parseResultFromContainer(element, category);
              if (result != null) {
                results.add(result);
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error parsing advanced element: $e');
            }
          }
          elementsProcessed++;
        }

        if (kDebugMode) {
          debugPrint('Found ${results.length} results from advanced search');
        }
      }

      // Filtra solo i risultati che coinvolgono Aurora Seriate
      final auroraResults = results.where((result) =>
        result.homeTeam.toLowerCase().contains('aurora') ||
        result.awayTeam.toLowerCase().contains('aurora')
      ).toList();

      if (kDebugMode) {
        debugPrint('=== TUTTOCAMPO PARSING RESULTS FOR $category ===');
        debugPrint('Total results found: ${results.length}');
        debugPrint('Aurora results found: ${auroraResults.length}');
        debugPrint('Elements processed: $elementsProcessed/$_maxElementsToProcess');

        if (auroraResults.isNotEmpty) {
          debugPrint('Aurora matches found:');
          for (final match in auroraResults) {
            debugPrint('  - ${match.homeTeam} vs ${match.awayTeam}: ${match.homeScore}-${match.awayScore}');
          }
        } else {
          debugPrint('NO Aurora matches found in category $category');
          if (results.isNotEmpty) {
            debugPrint('Sample of other results found:');
            for (int i = 0; i < math.min(3, results.length); i++) {
              debugPrint('  - ${results[i].homeTeam} vs ${results[i].awayTeam}: ${results[i].homeScore}-${results[i].awayScore}');
            }
          }
        }
        debugPrint('================================================');
      }

      return auroraResults;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing document for $category: $e');
      }
      return [];
    }
  }

  /// Parse risultati da una tabella - MIGLIORATO per contenuto dinamico
  static List<MatchResult> _parseResultsFromTable(Element table, String category) {
    final List<MatchResult> results = [];

    if (kDebugMode) {
      debugPrint('=== TUTTOCAMPO TABLE DEBUG ===');
      debugPrint('Table classes: ${table.className}');
      debugPrint('Table HTML preview: ${table.outerHtml.length > 500 ? table.outerHtml.substring(0, 500) : table.outerHtml}...');
    }

    // STRATEGIA 1: Cerca righe .match (struttura statica)
    final matchRows = table.querySelectorAll('tr.match');
    if (kDebugMode) {
      debugPrint('Found ${matchRows.length} tr.match rows (static structure)');
    }

    if (matchRows.isNotEmpty) {
      for (final row in matchRows) {
        try {
          final result = _parseTuttocampoMatchRow(row, category);
          if (result != null) {
            results.add(result);
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error parsing tuttocampo match row: $e');
          }
        }
      }
    }

    // STRATEGIA 2: Parsing avanzato per contenuto dinamico
    if (results.isEmpty) {
      if (kDebugMode) {
        debugPrint('No static matches found, trying dynamic content parsing...');
      }

      final allRows = table.querySelectorAll('tr');
      if (kDebugMode) {
        debugPrint('Total table rows: ${allRows.length}');
      }

      for (int i = 0; i < allRows.length && i < 50; i++) {
        final row = allRows[i];
        final rowText = row.text.toLowerCase();

        if (kDebugMode && i < 5) {
          debugPrint('Row $i classes: "${row.className}"');
          debugPrint('Row $i text: "${rowText.length > 100 ? rowText.substring(0, 100) : rowText}..."');
        }

        // Cerca righe che contengono Aurora
        if (rowText.contains('aurora')) {
          if (kDebugMode) {
            debugPrint('*** Aurora found in row $i! ***');
            debugPrint('Full row text: "$rowText"');
          }

          try {
            // Prova parsing celle standard
            final cells = row.querySelectorAll('td, th');
            if (cells.length >= 3) {
              final result = _parseResultFromCells(cells, category);
              if (result != null) {
                results.add(result);
                if (kDebugMode) {
                  debugPrint('✅ Parsed from dynamic row: ${result.homeTeam} vs ${result.awayTeam} (${result.homeScore}-${result.awayScore})');
                }
              }
            }

            // Prova anche parsing del testo generale
            final textResult = _parseResultFromRowText(row, category);
            if (textResult != null && !results.any((r) =>
                r.homeTeam == textResult.homeTeam &&
                r.awayTeam == textResult.awayTeam)) {
              results.add(textResult);
              if (kDebugMode) {
                debugPrint('✅ Parsed from row text: ${textResult.homeTeam} vs ${textResult.awayTeam} (${textResult.homeScore}-${textResult.awayScore})');
              }
            }
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error parsing Aurora row: $e');
            }
          }
        }
      }
    }

    if (kDebugMode) {
      debugPrint('Table parsing results: ${results.length} matches found');
      for (final result in results) {
        debugPrint('  - ${result.homeTeam} vs ${result.awayTeam}: ${result.homeScore}-${result.awayScore}');
      }
    }

    return results;
  }

  /// Parse risultato da celle di tabella
  static MatchResult? _parseResultFromCells(List<Element> cells, String category) {
    if (cells.length < 3) return null;

    try {
      String? dateText, timeText, homeTeam, awayTeam, scoreText;

      // Prova diversi formati di tabella
      if (cells.length >= 5) {
        // Formato: Data | Ora | Casa | Ospite | Risultato
        dateText = cells[0].text.trim();
        timeText = cells[1].text.trim();
        homeTeam = cells[2].text.trim();
        awayTeam = cells[3].text.trim();
        scoreText = cells[4].text.trim();
      } else if (cells.length == 4) {
        // Formato: Data | Casa | Ospite | Risultato
        final firstCell = cells[0].text.trim();
        if (RegExp(r'\d+[/\-\.]\d+').hasMatch(firstCell)) {
          dateText = firstCell;
          homeTeam = cells[1].text.trim();
          awayTeam = cells[2].text.trim();
          scoreText = cells[3].text.trim();
        } else {
          // Formato: Casa | Ospite | Risultato | Data
          homeTeam = cells[0].text.trim();
          awayTeam = cells[1].text.trim();
          scoreText = cells[2].text.trim();
          dateText = cells[3].text.trim();
        }
      } else if (cells.length == 3) {
        // Formato: Casa | Ospite | Risultato
        homeTeam = cells[0].text.trim();
        awayTeam = cells[1].text.trim();
        scoreText = cells[2].text.trim();
      }

      // Verifica che almeno le squadre siano presenti
      if (homeTeam == null || awayTeam == null || homeTeam.isEmpty || awayTeam.isEmpty) {
        return null;
      }

      // Verifica se Aurora è coinvolta
      if (!homeTeam.toLowerCase().contains('aurora') &&
          !awayTeam.toLowerCase().contains('aurora')) {
        return null;
      }

      // Parse del punteggio
      final scores = _parseScore(scoreText ?? '');
      if (scores == null) return null;

      // Parse della data (usa oggi se non specificata)
      final matchDate = _parseDateTime(dateText ?? '', timeText ?? '') ?? DateTime.now();

      return MatchResult(
        id: '${category}_${homeTeam}_${awayTeam}_${matchDate.millisecondsSinceEpoch}',
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeScore: scores['home']!,
        awayScore: scores['away']!,
        matchDate: matchDate,
        category: category,
        championship: _getChampionshipName(category),
      );

    } catch (e) {
      return null;
    }
  }

  /// Parse specifico per riga tuttocampo tr.match - AGGIORNATO con HTML reale
  static MatchResult? _parseTuttocampoMatchRow(Element row, String category) {
    try {
      if (kDebugMode) {
        debugPrint('Parsing tuttocampo match row for $category');
        debugPrint('Row HTML: ${row.outerHtml}');
      }

      // STRUTTURA REALE dal tuo HTML:
      // <tr class="match">
      //   <td class="match-time">...</td>
      //   <td class="team home">
      //     <a href="..."><span class="logo">...</span></a>
      //     <a class="team-name" href="...">Aurora Seriate 1967</a>
      //     <a href="...Partita/..."><span class="goal">3</span></a>
      //   </td>
      //   <td class="team away">
      //     <a href="..."><span class="logo">...</span></a>
      //     <a class="team-name" href="...">Falco</a>
      //     <a href="...Partita/..."><span class="goal">2</span></a>
      //   </td>
      //   <td class="details">...</td>
      // </tr>

      // Estrai celle principali
      final timeTd = row.querySelector('td.match-time');
      final homeTd = row.querySelector('td.team.home');
      final awayTd = row.querySelector('td.team.away');
      final detailsTd = row.querySelector('td.details');

      if (homeTd == null || awayTd == null) {
        if (kDebugMode) {
          debugPrint('Missing home or away team cell');
        }
        return null;
      }

      // Estrai nomi squadre dal link a.team-name
      final homeTeamElement = homeTd.querySelector('a.team-name');
      final awayTeamElement = awayTd.querySelector('a.team-name');

      final homeTeam = homeTeamElement?.text.trim() ?? '';
      final awayTeam = awayTeamElement?.text.trim() ?? '';

      if (kDebugMode) {
        debugPrint('Team names: home="$homeTeam", away="$awayTeam"');
      }

      if (homeTeam.isEmpty || awayTeam.isEmpty) {
        if (kDebugMode) {
          debugPrint('Empty team names');
        }
        return null;
      }

      // Verifica se Aurora è coinvolta (case insensitive)
      final hasAurora = homeTeam.toLowerCase().contains('aurora') ||
                       awayTeam.toLowerCase().contains('aurora');

      if (!hasAurora) {
        if (kDebugMode) {
          debugPrint('Aurora not involved in: $homeTeam vs $awayTeam');
        }
        return null;
      }

      // Estrai punteggi dai span.goal dentro i link
      // Nel tuo HTML: <a href="...Partita/..."><span class="goal">3</span></a>
      final homeScoreElement = homeTd.querySelector('a[href*="Partita"] span.goal');
      final awayScoreElement = awayTd.querySelector('a[href*="Partita"] span.goal');

      String homeScoreText = homeScoreElement?.text.trim() ?? '';
      String awayScoreText = awayScoreElement?.text.trim() ?? '';

      // Fallback: cerca span.goal anche fuori dai link
      if (homeScoreText.isEmpty) {
        final homeScoreSpan = homeTd.querySelector('span.goal');
        homeScoreText = homeScoreSpan?.text.trim() ?? '';
      }
      if (awayScoreText.isEmpty) {
        final awayScoreSpan = awayTd.querySelector('span.goal');
        awayScoreText = awayScoreSpan?.text.trim() ?? '';
      }

      if (kDebugMode) {
        debugPrint('Score texts: home="$homeScoreText", away="$awayScoreText"');
      }

      // Gestisci partite non giocate
      if (homeScoreText == '-' || awayScoreText == '-' ||
          homeScoreText.isEmpty || awayScoreText.isEmpty) {
        if (kDebugMode) {
          debugPrint('Match not played yet: $homeTeam vs $awayTeam');
        }
        return null;
      }

      // Parse dei punteggi
      final homeScore = int.tryParse(homeScoreText);
      final awayScore = int.tryParse(awayScoreText);

      if (homeScore == null || awayScore == null) {
        if (kDebugMode) {
          debugPrint('Could not parse scores: home="$homeScoreText" -> $homeScore, away="$awayScoreText" -> $awayScore');
        }
        return null;
      }

      // Validazione punteggi ragionevoli
      if (homeScore < 0 || awayScore < 0 || homeScore > 50 || awayScore > 50) {
        if (kDebugMode) {
          debugPrint('Invalid scores: $homeScore-$awayScore');
        }
        return null;
      }

      // Estrai ora/data dal td.match-time
      String timeText = '';
      String dateText = '';

      if (timeTd != null) {
        final timeElement = timeTd.querySelector('span.hour');
        timeText = timeElement?.text.trim() ?? '';

        // Cerca data nel contenuto della cella tempo
        final cellText = timeTd.text.trim();
        final dateMatch = RegExp(r'(\d{1,2}/\d{1,2})').firstMatch(cellText);
        if (dateMatch != null) {
          dateText = dateMatch.group(1) ?? '';
          // Aggiungi anno corrente
          if (dateText.isNotEmpty) {
            dateText = '$dateText/${DateTime.now().year}';
          }
        }
      }

      // Parse della data
      final matchDate = _parseDateTime(dateText, timeText) ?? DateTime.now();

      if (kDebugMode) {
        debugPrint('✅ MATCH PARSED: $homeTeam $homeScore-$awayScore $awayTeam');
        debugPrint('  Date: $dateText, Time: $timeText -> $matchDate');
      }

      return MatchResult(
        id: '${category}_${homeTeam}_${awayTeam}_${matchDate.millisecondsSinceEpoch}',
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeScore: homeScore,
        awayScore: awayScore,
        matchDate: matchDate,
        category: category,
        championship: _getChampionshipName(category),
      );

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing tuttocampo match row: $e');
      }
      return null;
    }
  }

  /// Parse risultato dal testo di una riga (per contenuto dinamico)
  static MatchResult? _parseResultFromRowText(Element row, String category) {
    try {
      final rowText = row.text.trim();

      if (kDebugMode) {
        debugPrint('Parsing row text: "$rowText"');
      }

      // Pattern migliorati per diverse strutture
      final patterns = [
        // Pattern "Aurora Seriate 1967 3 - 2 Falco"
        RegExp(r'(aurora seriate[^0-9]*?)\s*(\d+)\s*[-–—]\s*(\d+)\s*([^0-9\n\r]+)', caseSensitive: false),
        // Pattern "Falco 2 - 3 Aurora Seriate 1967"
        RegExp(r'([^0-9\n\r]+?)\s*(\d+)\s*[-–—]\s*(\d+)\s*(aurora seriate[^0-9]*)', caseSensitive: false),
        // Pattern tabellare separato da tab/spazi
        RegExp(r'(aurora seriate[^\t\n\r0-9]*?)[\t\s]+([^\t\n\r]*?)[\t\s]+(\d+)[\t\s]*[-–—][\t\s]*(\d+)', caseSensitive: false),
        RegExp(r'([^\t\n\r]*?)[\t\s]+(aurora seriate[^\t\n\r0-9]*?)[\t\s]+(\d+)[\t\s]*[-–—][\t\s]*(\d+)', caseSensitive: false),
        // Pattern con data/ora inclusa
        RegExp(r'(\d{1,2}[:/]\d{2}).*?(aurora seriate[^0-9]*?)\s*(\d+)\s*[-–—]\s*(\d+)\s*([^0-9\n\r]+)', caseSensitive: false),
        RegExp(r'(\d{1,2}[:/]\d{2}).*?([^0-9\n\r]+?)\s*(\d+)\s*[-–—]\s*(\d+)\s*(aurora seriate[^0-9]*)', caseSensitive: false),
      ];

      for (int i = 0; i < patterns.length; i++) {
        final pattern = patterns[i];
        final match = pattern.firstMatch(rowText);

        if (match != null) {
          if (kDebugMode) {
            debugPrint('Match found with pattern $i: ${pattern.pattern}');
            debugPrint('Groups: ${match.groupCount}');
            for (int g = 0; g <= match.groupCount; g++) {
              debugPrint('  Group $g: "${match.group(g)}"');
            }
          }

          String? homeTeam, awayTeam;
          int? homeScore, awayScore;

          // Determina l'ordine delle squadre in base al pattern
          if (i == 0 || i == 2 || i == 4) {
            // Aurora è la squadra di casa
            homeTeam = match.group(1)?.trim();
            homeScore = int.tryParse(match.group(2) ?? '');
            awayScore = int.tryParse(match.group(3) ?? '');
            awayTeam = match.group(4)?.trim();
          } else if (i == 1 || i == 3 || i == 5) {
            // Aurora è la squadra ospite
            homeTeam = match.group(1)?.trim();
            homeScore = int.tryParse(match.group(2) ?? '');
            awayScore = int.tryParse(match.group(3) ?? '');
            awayTeam = match.group(4)?.trim();
          }

          // Pulizia dei nomi delle squadre
          if (homeTeam != null) {
            homeTeam = homeTeam.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (homeTeam.length > 50) homeTeam = homeTeam.substring(0, 50).trim();
          }
          if (awayTeam != null) {
            awayTeam = awayTeam.replaceAll(RegExp(r'\s+'), ' ').trim();
            if (awayTeam.length > 50) awayTeam = awayTeam.substring(0, 50).trim();
          }

          // Validazione
          if (homeTeam != null && awayTeam != null &&
              homeScore != null && awayScore != null &&
              homeTeam.isNotEmpty && awayTeam.isNotEmpty &&
              homeScore >= 0 && awayScore >= 0 &&
              homeScore <= 50 && awayScore <= 50) {

            if (kDebugMode) {
              debugPrint('✅ Valid match extracted: $homeTeam $homeScore-$awayScore $awayTeam');
            }

            return MatchResult(
              id: '${category}_${homeTeam}_${awayTeam}_${DateTime.now().millisecondsSinceEpoch}',
              homeTeam: homeTeam,
              awayTeam: awayTeam,
              homeScore: homeScore,
              awayScore: awayScore,
              matchDate: DateTime.now(),
              category: category,
              championship: _getChampionshipName(category),
            );
          }
        }
      }

      if (kDebugMode) {
        debugPrint('No valid pattern matched for row text');
      }
      return null;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing row text: $e');
      }
      return null;
    }
  }

  /// Parse di una riga della tabella risultati
  static MatchResult? _parseResultRow(Element row, String category) {
    final cells = row.querySelectorAll('td');
    if (cells.length < 4) return null;

    try {
      // Estrai i dati dalle celle (formato tipico tuttocampo)
      final dateText = cells[0].text.trim();
      final timeText = cells[1].text.trim();
      final homeTeam = cells[2].text.trim();
      final awayTeam = cells[3].text.trim();
      final scoreText = cells[4].text.trim();

      // Verifica se Aurora Seriate è coinvolta
      if (!homeTeam.toUpperCase().contains('AURORA') &&
          !awayTeam.toUpperCase().contains('AURORA')) {
        return null;
      }

      // Parse della data e ora
      final matchDate = _parseDateTime(dateText, timeText);
      if (matchDate == null) return null;

      // Parse del punteggio
      final scores = _parseScore(scoreText);
      if (scores == null) return null;

      return MatchResult(
        id: '${category}_${homeTeam}_${awayTeam}_${matchDate.millisecondsSinceEpoch}',
        homeTeam: homeTeam,
        awayTeam: awayTeam,
        homeScore: scores['home']!,
        awayScore: scores['away']!,
        matchDate: matchDate,
        category: category,
        championship: _getChampionshipName(category),
        round: _extractRound(row),
        venue: _extractVenue(row),
      );

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing result row: $e');
      }
      return null;
    }
  }

  /// Parse risultato da un container div/span
  static MatchResult? _parseResultFromContainer(Element container, String category) {
    try {
      final text = container.text.trim();

      // Verifica se Aurora Seriate è coinvolta
      if (!text.toUpperCase().contains('AURORA')) {
        return null;
      }

      // Prima prova a cercare i nomi delle squadre e il punteggio separatamente
      final teamElements = container.querySelectorAll('.home-team, .away-team, .team-name, .team, .squadra');
      final scoreElements = container.querySelectorAll('.score, .result, .punteggio, .home-score, .away-score');

      String? homeTeam, awayTeam;
      int? homeScore, awayScore;

      // Estrai squadre da elementi specifici
      if (teamElements.length >= 2) {
        homeTeam = teamElements[0].text.trim();
        awayTeam = teamElements[1].text.trim();
      }

      // Estrai punteggi da elementi specifici
      if (scoreElements.length >= 2) {
        homeScore = int.tryParse(scoreElements[0].text.trim());
        awayScore = int.tryParse(scoreElements[1].text.trim());
      } else if (scoreElements.length == 1) {
        // Potrebbe essere in formato "X-Y"
        final scoreText = scoreElements[0].text.trim();
        final scoreMatch = RegExp(r'(\d+)\s*[-–—]\s*(\d+)').firstMatch(scoreText);
        if (scoreMatch != null) {
          homeScore = int.tryParse(scoreMatch.group(1) ?? '');
          awayScore = int.tryParse(scoreMatch.group(2) ?? '');
        }
      }

      // Se non ha trovato squadre/punteggi negli elementi, prova pattern nel testo
      if (homeTeam == null || awayTeam == null || homeScore == null || awayScore == null) {
        // Pattern migliorati per tuttocampo
        final patterns = [
          // "Aurora Seriate 2-1 Scanzorosciate"
          RegExp(r'(aurora[^0-9]*?)\s*(\d+)\s*[-–—]\s*(\d+)\s*([^0-9]+)', caseSensitive: false),
          // "Caravaggio 0-3 Aurora Seriate"
          RegExp(r'([^0-9]+?)\s*(\d+)\s*[-–—]\s*(\d+)\s*(aurora[^0-9]*)', caseSensitive: false),
          // Formato tabellare: "Casa | Ospite | 2-1"
          RegExp(r'(aurora[^|]*)\s*\|\s*([^|]*)\s*\|\s*(\d+)\s*[-–—]\s*(\d+)', caseSensitive: false),
          RegExp(r'([^|]*)\s*\|\s*(aurora[^|]*)\s*\|\s*(\d+)\s*[-–—]\s*(\d+)', caseSensitive: false),
          // Pattern generico migliorato
          RegExp(r'([A-Za-z\s]+)\s+(\d+)\s*[-–—]\s*(\d+)\s+([A-Za-z\s]+)', caseSensitive: false),
        ];

        for (final pattern in patterns) {
          final match = pattern.firstMatch(text);
          if (match != null) {
            if (pattern.pattern.contains('aurora[^|]*\\|')) {
              // Formato tabellare con Aurora come casa
              homeTeam = match.group(1)!.trim();
              awayTeam = match.group(2)!.trim();
              homeScore = int.tryParse(match.group(3) ?? '');
              awayScore = int.tryParse(match.group(4) ?? '');
            } else if (pattern.pattern.contains('\\|(aurora[^|]*)')) {
              // Formato tabellare con Aurora come ospite
              homeTeam = match.group(1)!.trim();
              awayTeam = match.group(2)!.trim();
              homeScore = int.tryParse(match.group(3) ?? '');
              awayScore = int.tryParse(match.group(4) ?? '');
            } else {
              // Formato standard
              homeTeam = match.group(1)!.trim();
              homeScore = int.tryParse(match.group(2) ?? '');
              awayScore = int.tryParse(match.group(3) ?? '');
              awayTeam = match.group(4)!.trim();
            }
            break;
          }
        }
      }

      // Verifica che tutti i valori siano validi
      if (homeTeam != null && awayTeam != null && homeScore != null && awayScore != null &&
          homeScore >= 0 && awayScore >= 0 && homeScore <= 20 && awayScore <= 20) {

        // Cerca data nel container o nei suoi elementi
        final dateElement = container.querySelector('.date, .data, time, .match-date') ?? container;
        final dateText = _extractDateFromElement(dateElement);
        final matchDate = _parseDateTime(dateText ?? '', '') ?? DateTime.now();

        return MatchResult(
          id: '${category}_${homeTeam}_${awayTeam}_${matchDate.millisecondsSinceEpoch}',
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          homeScore: homeScore,
          awayScore: awayScore,
          matchDate: matchDate,
          category: category,
          championship: _getChampionshipName(category),
        );
      }

      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing container: $e');
      }
      return null;
    }
  }

  /// Parse risultato da un elemento di lista
  static MatchResult? _parseResultFromListItem(Element item, String category) {
    try {
      final text = item.text.trim();

      // Verifica se Aurora Seriate è coinvolta
      if (!text.toUpperCase().contains('AURORA')) {
        return null;
      }

      // Usa la stessa logica del container
      return _parseResultFromContainer(item, category);
    } catch (e) {
      return null;
    }
  }

  /// Estrae una data da un elemento
  static String? _extractDateFromElement(Element element) {
    // Cerca pattern di data nel testo
    final text = element.text;
    final datePattern = RegExp(r'(\d{1,2})[/\-\.](\d{1,2})[/\-\.](\d{2,4})');
    final match = datePattern.firstMatch(text);

    if (match != null) {
      return match.group(0);
    }

    // Cerca anche pattern di data italiana
    final italianDatePattern = RegExp(r'(\d{1,2})\s+(gennaio|febbraio|marzo|aprile|maggio|giugno|luglio|agosto|settembre|ottobre|novembre|dicembre)\s+(\d{4})');
    final italianMatch = italianDatePattern.firstMatch(text);

    if (italianMatch != null) {
      final day = italianMatch.group(1)!;
      final monthName = italianMatch.group(2)!;
      final year = italianMatch.group(3)!;

      final monthMap = {
        'gennaio': '01', 'febbraio': '02', 'marzo': '03', 'aprile': '04',
        'maggio': '05', 'giugno': '06', 'luglio': '07', 'agosto': '08',
        'settembre': '09', 'ottobre': '10', 'novembre': '11', 'dicembre': '12'
      };

      final month = monthMap[monthName] ?? '01';
      return '$day/$month/$year';
    }

    return null;
  }

  /// Parse della data e ora
  static DateTime? _parseDateTime(String dateText, String timeText) {
    try {
      if (dateText.isEmpty) return null;

      final dateFormat = DateFormat('dd/MM/yyyy');
      final date = dateFormat.parse(dateText);

      int hour = 0;
      int minute = 0;

      if (timeText.isNotEmpty) {
        try {
          final timeFormat = DateFormat('HH:mm');
          final time = timeFormat.parse(timeText);
          hour = time.hour;
          minute = time.minute;
        } catch (e) {
          // Se il parsing del tempo fallisce, usa ora 0:00
        }
      }

      return DateTime(
        date.year,
        date.month,
        date.day,
        hour,
        minute,
      );
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing date/time: $dateText $timeText - $e');
      }
      return null;
    }
  }

  /// Parse del punteggio
  static Map<String, int>? _parseScore(String scoreText) {
    try {
      // Rimuovi spazi e normalizza
      final cleanScore = scoreText.trim().replaceAll(RegExp(r'\s+'), ' ');

      // Pattern per punteggi normali (es: "2-1", "0-0")
      final scoreRegex = RegExp(r'(\d+)\s*-\s*(\d+)');
      final match = scoreRegex.firstMatch(cleanScore);

      if (match != null) {
        final homeScore = int.parse(match.group(1)!);
        final awayScore = int.parse(match.group(2)!);

        if (kDebugMode) {
          debugPrint('Parsed score: $homeScore-$awayScore from "$scoreText"');
        }

        return {
          'home': homeScore,
          'away': awayScore,
        };
      }

      // Se non trova pattern, potrebbe essere partita non giocata
      if (cleanScore.toLowerCase().contains('rinv') ||
          cleanScore.toLowerCase().contains('posticip') ||
          cleanScore.isEmpty) {
        if (kDebugMode) {
          debugPrint('Match not played yet: "$scoreText"');
        }
        return null; // Non includere partite non giocate
      }

      if (kDebugMode) {
        debugPrint('Could not parse score format: "$scoreText"');
      }
      return null;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing score: $scoreText - $e');
      }
      return null;
    }
  }

  /// Estrai informazioni sulla giornata
  static String? _extractRound(Element row) {
    try {
      final roundCell = row.querySelector('.giornata, .round');
      return roundCell?.text.trim();
    } catch (e) {
      return null;
    }
  }

  /// Estrai informazioni sul campo
  static String? _extractVenue(Element row) {
    try {
      final venueCell = row.querySelector('.campo, .venue');
      return venueCell?.text.trim();
    } catch (e) {
      return null;
    }
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

  /// Parse di una pagina di singola partita (nuovo formato URL)
  static List<MatchResult> _parseSingleMatchPage(Document document, String category) {
    final List<MatchResult> results = [];

    try {
      if (kDebugMode) {
        debugPrint('Parsing single match page for category: $category');
      }

      // Cerca i nomi delle squadre in diversi possibili selettori
      final teamSelectors = [
        '.team-name, .team, .squadra',
        'h1, h2, h3',
        '.match-title, .partita-title',
        '.home-team, .away-team',
        '[class*="team"], [class*="squadra"]'
      ];

      String? homeTeam;
      String? awayTeam;
      int homeScore = 0;
      int awayScore = 0;

      // Cerca nel titolo della pagina
      final title = document.querySelector('title')?.text ?? '';
      if (title.toLowerCase().contains('aurora')) {
        final titleMatch = RegExp(r'(.+?)\s+(?:vs|contro|-)\s+(.+)', caseSensitive: false).firstMatch(title);
        if (titleMatch != null) {
          homeTeam = titleMatch.group(1)?.trim();
          awayTeam = titleMatch.group(2)?.trim();
        }
      }

      // Cerca nei contenuti della pagina
      for (final selector in teamSelectors) {
        final elements = document.querySelectorAll(selector);
        for (final element in elements) {
          final text = element.text;
          if (text.toLowerCase().contains('aurora')) {
            // Prova a estrarre i nomi delle squadre
            final match = RegExp(r'(.+?)\s+(?:vs|contro|-|—)\s+(.+)', caseSensitive: false).firstMatch(text);
            if (match != null) {
              homeTeam = match.group(1)?.trim();
              awayTeam = match.group(2)?.trim();
              break;
            }
          }
        }
        if (homeTeam != null && awayTeam != null) break;
      }

      // PRIMA: Cerca la struttura specifica di tuttocampo
      final matchGoalDiv = document.querySelector('.match-goal');
      if (matchGoalDiv != null) {
        final homeSpan = matchGoalDiv.querySelector('.home, span.home');
        final awaySpan = matchGoalDiv.querySelector('.away, span.away');

        if (homeSpan != null && awaySpan != null) {
          final homeText = homeSpan.text.trim();
          final awayText = awaySpan.text.trim();
          final homeGoals = int.tryParse(homeText);
          final awayGoals = int.tryParse(awayText);

          if (homeGoals != null && awayGoals != null && homeGoals <= 20 && awayGoals <= 20) {
            homeScore = homeGoals;
            awayScore = awayGoals;

            if (kDebugMode) {
              debugPrint('✅ PUNTEGGIO TROVATO con struttura tuttocampo!');
              debugPrint('  Selettore: .match-goal');
              debugPrint('  Home (.home): $homeText -> $homeScore');
              debugPrint('  Away (.away): $awayText -> $awayScore');
              debugPrint('  Risultato: $homeScore-$awayScore');
            }
          } else {
            if (kDebugMode) {
              debugPrint('❌ Struttura tuttocampo trovata ma valori non validi:');
              debugPrint('  Home: "$homeText" -> $homeGoals');
              debugPrint('  Away: "$awayText" -> $awayGoals');
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('❌ .match-goal trovato ma mancano .home/.away');
          }
        }
      }

      // Se il metodo tuttocampo ha funzionato, salta i selettori generici
      if (homeScore > 0 || awayScore > 0) {
        if (kDebugMode) {
          debugPrint('✅ Punteggio già trovato con struttura tuttocampo, saltando selettori generici');
        }
      } else {
        // FALLBACK: Cerca con selettori generici
        final scoreSelectors = [
          '.score, .punteggio, .risultato',
          '.match-score, .partita-score',
          '.result, .final-score',
          '[class*="score"], [class*="punteggio"], [class*="result"]',
          'h1, h2, h3', // Spesso il punteggio è nel titolo principale
        ];

        if (kDebugMode) {
          debugPrint('🔍 Struttura tuttocampo non trovata, cercando con selettori CSS generici...');
        }

      for (final selector in scoreSelectors) {
        final scoreElements = document.querySelectorAll(selector);
        if (kDebugMode && scoreElements.isNotEmpty) {
          debugPrint('Selettore "$selector" trovato ${scoreElements.length} elementi');
        }

        for (final element in scoreElements) {
          final scoreText = element.text.trim();
          if (kDebugMode && scoreText.isNotEmpty) {
            debugPrint('  Testo elemento: "$scoreText"');
          }

          // Pattern più specifico per punteggi ragionevoli
          final scoreMatch = RegExp(r'([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2})').firstMatch(scoreText);
          if (scoreMatch != null) {
            final score1 = int.tryParse(scoreMatch.group(1) ?? '0') ?? 0;
            final score2 = int.tryParse(scoreMatch.group(2) ?? '0') ?? 0;

            // Filtra punteggi ragionevoli
            if (score1 <= 20 && score2 <= 20) {
              if (kDebugMode) {
                debugPrint('✅ Punteggio VALIDO trovato: $score1-$score2 (selettore: $selector)');
              }
              homeScore = score1;
              awayScore = score2;
              break;
            } else {
              if (kDebugMode) {
                debugPrint('❌ Punteggio IGNORATO (troppo alto): $score1-$score2');
              }
            }
          }
        }
        if (homeScore > 0 || awayScore > 0) break;
      }
      } // Chiusura del blocco else

      // Se non trova punteggio nei selettori dedicati, cerca nel testo generale CON FILTRI
      if (homeScore == 0 && awayScore == 0) {
        final bodyText = document.body?.text ?? '';

        if (kDebugMode) {
          debugPrint('🔍 Cercando punteggio nel testo generale...');
          debugPrint('Preview testo: ${bodyText.length > 500 ? bodyText.substring(0, 500) : bodyText}...');
        }

        // Cerca pattern di punteggio più specifici (massimo 2 cifre per punteggio)
        final scorePatterns = [
          // Pattern specifico per tuttocampo: "Aurora ... 1 - 2 ..."
          RegExp(r'aurora.*?([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2})', caseSensitive: false),
          RegExp(r'([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2}).*?virescit', caseSensitive: false),
          // Pattern generici con filtri
          RegExp(r'\b([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2})\b'), // Pattern con word boundary
          RegExp(r'(?:^|\s)([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2})(?:\s|$)'), // Pattern con spazi
          RegExp(r'(?:punteggio|risultato|score).*?([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2})', caseSensitive: false),
        ];

        for (final pattern in scorePatterns) {
          final matches = pattern.allMatches(bodyText);
          for (final match in matches) {
            final score1 = int.tryParse(match.group(1) ?? '0') ?? 0;
            final score2 = int.tryParse(match.group(2) ?? '0') ?? 0;

            // Filtra punteggi ragionevoli (0-20 per partita di calcio)
            if (score1 <= 20 && score2 <= 20) {
              if (kDebugMode) {
                debugPrint('✅ Punteggio trovato: $score1-$score2 (pattern: ${pattern.pattern})');
                debugPrint('Contesto: "${match.input.substring(
                  (match.start - 20).clamp(0, match.input.length),
                  (match.end + 20).clamp(0, match.input.length)
                )}"');
              }
              homeScore = score1;
              awayScore = score2;
              break;
            } else {
              if (kDebugMode) {
                debugPrint('❌ Punteggio ignorato (troppo alto): $score1-$score2');
              }
            }
          }
          if (homeScore > 0 || awayScore > 0) break;
        }

        if (homeScore == 0 && awayScore == 0) {
          if (kDebugMode) {
            debugPrint('❌ Nessun punteggio valido trovato nel testo generale');
          }
        }
      }

      // Prova a estrarre la data
      DateTime matchDate = DateTime.now();
      final dateSelectors = ['.date, .data', '.match-date'];
      for (final selector in dateSelectors) {
        final dateElement = document.querySelector(selector);
        if (dateElement != null) {
          final dateText = dateElement.text;
          final extractedDate = _parseDateTime(dateText, '');
          if (extractedDate != null) {
            matchDate = extractedDate;
            break;
          }
        }
      }

      if (homeTeam != null && awayTeam != null) {
        final result = MatchResult(
          homeTeam: homeTeam,
          awayTeam: awayTeam,
          homeScore: homeScore,
          awayScore: awayScore,
          matchDate: matchDate,
          category: category,
          championship: _getChampionshipName(category),
        );

        results.add(result);

        if (kDebugMode) {
          debugPrint('✅ Single match parsed: $homeTeam vs $awayTeam ($homeScore-$awayScore)');
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ Could not extract team names from single match page');
          debugPrint('Title: $title');
          debugPrint('Body text preview: ${document.body?.text.substring(0, 200) ?? "No body"}...');
        }
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error parsing single match page: $e');
      }
    }

    return results;
  }

  /// Test specifico per U21 TERZA - sabato 27/09
  static Future<List<MatchResult>> testU21Scraping() async {
    if (kDebugMode) {
      debugPrint('=== TEST SPECIFICO U21 TERZA - SABATO 27/09 ===');
      debugPrint('Partita attesa: AURORA SERIATE vs VIRESCIT (o PONTE SAN PIETRO)');
      debugPrint('Categoria: U21 TERZA');
      debugPrint('URL principale: $_baseUrl/Lombardia/Under21/GironeD/Risultati');
      debugPrint('URL specifico Aurora: $_baseUrl/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit');
    }

    try {
      // PRIMA prova l'URL specifico della partita Aurora
      if (kDebugMode) {
        debugPrint('🎯 STEP 1: Test URL specifico partita Aurora...');
      }

      final auroraSpecificResults = await scrapeCategoryResults(
        'U21 TERZA',
        '/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit'
      );

      if (auroraSpecificResults.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ URL SPECIFICO AURORA FUNZIONA!');
          debugPrint('URL: $_baseUrl/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit');
          for (final result in auroraSpecificResults) {
            debugPrint('  - ${result.homeTeam} vs ${result.awayTeam}: ${result.homeScore}-${result.awayScore}');
          }
        }
        return auroraSpecificResults;
      }

      // Se l'URL specifico fallisce, prova quello principale
      if (kDebugMode) {
        debugPrint('🎯 STEP 2: URL specifico fallito, test URL principale...');
      }

      final mainResults = await scrapeCategoryResults('U21 TERZA', '/Lombardia/Under21/GironeD/Risultati');

      if (mainResults.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ URL PRINCIPALE FUNZIONA per U21!');
          for (final result in mainResults) {
            debugPrint('  - ${result.homeTeam} vs ${result.awayTeam}: ${result.homeScore}-${result.awayScore}');
          }
        }
        return mainResults;
      }

      // Se anche l'URL principale fallisce, prova gli altri alternativi
      if (kDebugMode) {
        debugPrint('❌ URL principale fallito, provando URL alternativi...');
      }

      final alternativeUrls = _alternativeUrls['U21 TERZA'] ?? [];
      for (int i = 0; i < alternativeUrls.length; i++) {
        final altUrl = alternativeUrls[i];
        if (kDebugMode) {
          debugPrint('Tentativo ${i + 1}/${alternativeUrls.length}: $_baseUrl$altUrl');
        }

        try {
          final altResults = await scrapeCategoryResults('U21 TERZA', altUrl);
          if (altResults.isNotEmpty) {
            if (kDebugMode) {
              debugPrint('✅ URL ALTERNATIVO FUNZIONA: $_baseUrl$altUrl');
              for (final result in altResults) {
                debugPrint('  - ${result.homeTeam} vs ${result.awayTeam}: ${result.homeScore}-${result.awayScore}');
              }
            }
            return altResults;
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ URL alternativo fallito: $e');
          }
        }
      }

      if (kDebugMode) {
        debugPrint('❌ TUTTI GLI URL FALLITI per U21 TERZA');
        debugPrint('Possibili cause:');
        debugPrint('  1. Tuttocampo.it sta bloccando tutte le richieste');
        debugPrint('  2. Struttura URL cambiata');
        debugPrint('  3. Partita non ancora inserita nei risultati');
      }

      return [];

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ERRORE GENERALE nel test U21: $e');
      }
      return [];
    }
  }

  /// Test diretto dell'URL specifico fornito dall'utente per U21
  static Future<void> testSpecificU21Url() async {
    const specificUrl = 'https://www.tuttocampo.it/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit';

    if (kDebugMode) {
      debugPrint('=== TEST DIRETTO URL SPECIFICO U21 ===');
      debugPrint('URL: $specificUrl');
      debugPrint('Testando accesso diretto...');
    }

    try {
      final response = await http.get(
        Uri.parse(specificUrl),
        headers: _headers,
      ).timeout(const Duration(seconds: 30));

      if (kDebugMode) {
        debugPrint('Status Code: ${response.statusCode}');
        debugPrint('Content Length: ${response.body.length}');

        if (response.statusCode == 200) {
          debugPrint('✅ URL ACCESSIBILE!');

          final document = html_parser.parse(response.body);
          final title = document.querySelector('title')?.text ?? 'No title';
          debugPrint('Page Title: $title');

          // Cerca Aurora nel contenuto
          final bodyText = document.body?.text ?? '';
          final hasAurora = bodyText.toLowerCase().contains('aurora');
          debugPrint('Contiene "Aurora": $hasAurora');

          if (hasAurora) {
            debugPrint('✅ Pagina contiene informazioni Aurora!');

            // Debug: cerca prima la struttura tuttocampo specifica
            if (kDebugMode) {
              debugPrint('🔍 RICERCA STRUTTURA TUTTOCAMPO:');
              final matchGoalDiv = document.querySelector('.match-goal');
              if (matchGoalDiv != null) {
                debugPrint('✅ Trovato div .match-goal!');
                final homeSpan = matchGoalDiv.querySelector('.home, span.home');
                final awaySpan = matchGoalDiv.querySelector('.away, span.away');
                final dividerSpan = matchGoalDiv.querySelector('.divider');

                debugPrint('  .home span: ${homeSpan?.text.trim() ?? "NON TROVATO"}');
                debugPrint('  .divider span: ${dividerSpan?.text.trim() ?? "NON TROVATO"}');
                debugPrint('  .away span: ${awaySpan?.text.trim() ?? "NON TROVATO"}');
                debugPrint('  HTML completo: ${matchGoalDiv.outerHtml}');
              } else {
                debugPrint('❌ Div .match-goal NON trovato');
              }

              debugPrint('🔍 ANALISI PATTERN ALTERNATIVI:');
              final allScoreMatches = RegExp(r'([0-9]{1,2})\s*[-–—]\s*([0-9]{1,2})').allMatches(bodyText);
              debugPrint('Tutti i pattern X-X trovati: ${allScoreMatches.length}');
              for (final match in allScoreMatches.take(5)) { // Mostra solo i primi 5
                final score1 = match.group(1);
                final score2 = match.group(2);
                final context = bodyText.substring(
                  (match.start - 30).clamp(0, bodyText.length),
                  (match.end + 30).clamp(0, bodyText.length)
                );
                debugPrint('  Punteggio: $score1-$score2 | Contesto: "...${context.replaceAll('\n', ' ')}..."');
              }
            }

            // Prova parsing
            final results = _parseResultsFromDocument(document, 'U21 TERZA');
            debugPrint('Risultati parsing: ${results.length}');

            for (final result in results) {
              debugPrint('  ✅ RISULTATO: ${result.homeTeam} vs ${result.awayTeam}: ${result.homeScore}-${result.awayScore}');
            }
          } else {
            debugPrint('❌ Pagina non contiene informazioni Aurora');
          }
        } else {
          debugPrint('❌ URL NON ACCESSIBILE - HTTP ${response.statusCode}');
          if (response.statusCode == 403) {
            debugPrint('Tuttocampo sta bloccando le richieste');
          }
        }
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ ERRORE accesso URL: $e');
      }
    }
  }

  /// Test di connettività al sito
  static Future<bool> testConnection() async {
    try {
      final response = await http.get(
        Uri.parse('$_baseUrl/Lombardia/JunioresEliteU19/GironeC/Risultati'),
        headers: _headers,
      );

      return response.statusCode == 200;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Connection test failed: $e');
      }
      return false;
    }
  }

  /// Test migliorato per il parsing con debug dettagliato
  static Future<List<MatchResult>> testImprovedParsing() async {
    if (kDebugMode) {
      debugPrint('=== TEST PARSING MIGLIORATO ===');
      debugPrint('Testing improved CSS selectors and regex patterns');
    }

    final List<MatchResult> allResults = [];

    // Test su tutte le categorie con nuovi miglioramenti
    for (final entry in _auroraUrls.entries) {
      try {
        if (kDebugMode) {
          debugPrint('--- Testing category: ${entry.key} ---');
        }

        final categoryResults = await _scrapeCategory(entry.key, entry.value);
        allResults.addAll(categoryResults);

        if (kDebugMode) {
          debugPrint('Category ${entry.key}: ${categoryResults.length} results found');
          for (final result in categoryResults) {
            debugPrint('  ✅ ${result.homeTeam} vs ${result.awayTeam}: ${result.homeScore}-${result.awayScore}');
          }
        }

        // Pausa tra test
        await Future.delayed(const Duration(milliseconds: 800));
      } catch (e) {
        if (kDebugMode) {
          debugPrint('Error testing ${entry.key}: $e');
        }
      }
    }

    if (kDebugMode) {
      debugPrint('=== RISULTATI FINALI TEST ===');
      debugPrint('Totale risultati trovati: ${allResults.length}');
      debugPrint('Categorie con risultati:');

      final categoryCount = <String, int>{};
      for (final result in allResults) {
        final category = result.category ?? 'Sconosciuta';
        categoryCount[category] = (categoryCount[category] ?? 0) + 1;
      }

      categoryCount.forEach((category, count) {
        debugPrint('  $category: $count risultati');
      });
    }

    return allResults;
  }

  /// Parsing avanzato del testo per ambienti web (alternativa a WebView)
  static List<MatchResult> _tryAdvancedTextParsing(String bodyText, String category) {
    final List<MatchResult> results = [];

    try {
      if (kDebugMode) {
        debugPrint('🔍 Advanced text parsing for $category');
        debugPrint('Text length: ${bodyText.length} characters');
      }

      // Cerca Aurora nel testo e analizza il contesto
      final auroraPattern = RegExp(r'aurora[^\n\r]{0,300}', caseSensitive: false);
      final auroraMatches = auroraPattern.allMatches(bodyText);

      if (kDebugMode) {
        debugPrint('Aurora contexts found: ${auroraMatches.length}');
      }

      for (final auroraMatch in auroraMatches) {
        final context = auroraMatch.group(0) ?? '';

        if (kDebugMode) {
          debugPrint('Context: "$context"');
        }

        // Pattern più flessibili per JSON/JavaScript embedded
        final scorePatterns = [
          // Pattern per dati JSON
          RegExp(r'aurora[^"]*"[^"]*(\d+)[^"]*"[^"]*(\d+)', caseSensitive: false),
          RegExp(r'(\d+)[^"]*"[^"]*(\d+)[^"]*aurora', caseSensitive: false),
          // Pattern per contenuto script
          RegExp(r'aurora[^;]*(\d+).*?(\d+)', caseSensitive: false),
          RegExp(r'(\d+).*?(\d+)[^;]*aurora', caseSensitive: false),
          // Pattern per URL/parametri
          RegExp(r'aurora.*?=(\d+).*?=(\d+)', caseSensitive: false),
          RegExp(r'(\d+).*?(\d+).*?aurora', caseSensitive: false),
        ];

        for (final pattern in scorePatterns) {
          final matches = pattern.allMatches(context);

          for (final match in matches) {
            try {
              final score1 = int.tryParse(match.group(1) ?? '');
              final score2 = int.tryParse(match.group(2) ?? '');

              if (score1 != null && score2 != null &&
                  score1 >= 0 && score2 >= 0 &&
                  score1 <= 20 && score2 <= 20) {

                // Cerca squadra avversaria nel contesto
                String opponent = 'Unknown';
                final opponentPatterns = [
                  RegExp(r'vs\s+([a-z\s]+)', caseSensitive: false),
                  RegExp(r'contro\s+([a-z\s]+)', caseSensitive: false),
                  RegExp(r'([a-z\s]+)\s+vs', caseSensitive: false),
                ];

                for (final opPattern in opponentPatterns) {
                  final opMatch = opPattern.firstMatch(context);
                  if (opMatch != null) {
                    opponent = opMatch.group(1)?.trim() ?? 'Unknown';
                    break;
                  }
                }

                final result = MatchResult(
                  id: '${category}_Aurora_${opponent}_${DateTime.now().millisecondsSinceEpoch}',
                  homeTeam: 'Aurora Seriate 1967',
                  awayTeam: opponent,
                  homeScore: score1,
                  awayScore: score2,
                  matchDate: DateTime.now(),
                  category: category,
                  championship: _getChampionshipName(category),
                );

                results.add(result);

                if (kDebugMode) {
                  debugPrint('✅ Found match: Aurora $score1-$score2 $opponent');
                }
              }
            } catch (e) {
              // Continue with next pattern
            }
          }
        }
      }

      // Se non trova con Aurora, cerca pattern generali di punteggio
      if (results.isEmpty) {
        final genericScorePattern = RegExp(r'(\d+)\s*[-–—:]\s*(\d+)');
        final scoreMatches = genericScorePattern.allMatches(bodyText);

        if (kDebugMode) {
          debugPrint('Generic score patterns found: ${scoreMatches.length}');
        }

        // Analizza i primi 10 punteggi per vedere se ci sono indizi
        int analyzed = 0;
        for (final scoreMatch in scoreMatches) {
          if (analyzed >= 10) break;

          final start = (scoreMatch.start - 100).clamp(0, bodyText.length);
          final end = (scoreMatch.end + 100).clamp(0, bodyText.length);
          final context = bodyText.substring(start, end);

          if (context.toLowerCase().contains('aurora')) {
            final score1 = int.tryParse(scoreMatch.group(1) ?? '');
            final score2 = int.tryParse(scoreMatch.group(2) ?? '');

            if (score1 != null && score2 != null &&
                score1 >= 0 && score2 >= 0 &&
                score1 <= 20 && score2 <= 20) {

              final result = MatchResult(
                id: '${category}_Aurora_Generic_${DateTime.now().millisecondsSinceEpoch}',
                homeTeam: 'Aurora Seriate 1967',
                awayTeam: 'Opponent',
                homeScore: score1,
                awayScore: score2,
                matchDate: DateTime.now(),
                category: category,
                championship: _getChampionshipName(category),
              );

              results.add(result);

              if (kDebugMode) {
                debugPrint('✅ Found generic match: $score1-$score2 in context: "$context"');
              }
            }
          }
          analyzed++;
        }
      }

      if (kDebugMode) {
        debugPrint('Advanced parsing found ${results.length} results');
      }

      return results;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error in advanced text parsing: $e');
      }
      return <MatchResult>[];
    }
  }
}