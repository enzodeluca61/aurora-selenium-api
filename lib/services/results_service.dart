import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../models/result_model.dart';
import '../models/match_model.dart';
import 'selenium_api_service.dart';

class ResultsService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<MatchResult> _results = [];
  bool _isLoading = false;
  String? _errorMessage;

  // SELENIUM: Scraping veloce e affidabile con Selenium
  static const bool _scrapingEnabled = true; // Abilitato per leggere i risultati da tuttocampo

  List<MatchResult> get results => _results;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  ResultsService() {
    if (kDebugMode) {
      debugPrint('=== RESULTS SERVICE CONSTRUCTOR ===');
    }

    // Carica i risultati subito e ascolta i cambiamenti di autenticazione
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (kDebugMode) {
        debugPrint('=== POST FRAME CALLBACK TRIGGERED ===');
      }
      loadResults();
    });

    _supabase.auth.onAuthStateChange.listen((data) {
      if (kDebugMode) {
        debugPrint('=== AUTH STATE CHANGE ===');
        debugPrint('User: ${data.session?.user?.email}');
      }
      if (data.session?.user != null) {
        loadResults();
      } else {
        _results = [];
        notifyListeners();
      }
    });

    if (kDebugMode) {
      debugPrint('=== RESULTS SERVICE CONSTRUCTOR COMPLETE ===');
    }
  }

  Future<void> loadResults({DateTime? weekStart}) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== LOADING RESULTS ===');
        debugPrint('Current user: ${_supabase.auth.currentUser?.email}');
      }

      try {
        // Trova il primo giorno con partite agonistiche a partire da oggi (o dalla data specificata)
        final now = DateTime.now();
        DateTime targetDate = weekStart ?? DateTime(now.year, now.month, now.day);

        if (kDebugMode) {
          debugPrint('=== DATABASE QUERY FILTERING ===');
          debugPrint('Current date: $now');
          debugPrint('Starting search from: ${targetDate.toIso8601String()}');
          debugPrint('Looking for first day with agonistic matches...');
        }

        // Cerca il primo giorno con partite agonistiche (nei prossimi 14 giorni)
        List<dynamic> matchesResponse = [];
        int daysSearched = 0;
        final maxDaysToSearch = 14;

        while (matchesResponse.isEmpty && daysSearched < maxDaysToSearch) {
          final currentDate = targetDate.add(Duration(days: daysSearched));

          if (kDebugMode) {
            debugPrint('🔍 Checking ${currentDate.day}/${currentDate.month} for agonistic matches...');
          }

          // Query per il giorno specifico, solo categorie agonistiche
          matchesResponse = await _supabase
              .from('matches')
              .select()
              .not('aurora_team', 'is', null) // Solo partite con squadra Aurora specificata
              .eq('date', currentDate.toIso8601String().split('T')[0]) // Solo questo giorno
              .inFilter('aurora_team', ['PROMOZIONE', 'U21 TERZA', 'U19 JUNIORES ELITE', 'U18 ALLIEVI REG', 'U17 ALLIEVI REG', 'U16 ALLIEVI', 'U15 GIOVANISSIMI', 'U14 GIOVANISSIMI']) // Solo agonistiche
              .order('time', ascending: true);

          if (matchesResponse.isNotEmpty) {
            targetDate = currentDate;
            if (kDebugMode) {
              debugPrint('✅ Found ${matchesResponse.length} agonistic matches on ${targetDate.day}/${targetDate.month}/${targetDate.year}');
            }
            break;
          }

          daysSearched++;
        }

        if (matchesResponse.isEmpty) {
          if (kDebugMode) {
            debugPrint('❌ No agonistic matches found in the next $maxDaysToSearch days');
          }
        }

        if (kDebugMode) {
          debugPrint('Raw database response: ${matchesResponse.length} records');
          for (final rawMatch in matchesResponse) {
            debugPrint('Raw match: aurora_team="${rawMatch['aurora_team']}", opponent="${rawMatch['opponent']}", date="${rawMatch['date']}"');
          }
        }

        // Converte le partite del calendario in MatchResult con punteggi iniziali 0-0
        final matches = (matchesResponse as List)
            .map((json) => Match.fromJson(json))
            .toList();

        _results = [];
        for (final match in matches) {
          try {
            final result = _convertMatchToResult(match);
            _results.add(result);
          } catch (e) {
            if (kDebugMode) {
              debugPrint('Error converting match to result: ${match.opponent} - $e');
              debugPrint('Skipping this match to prevent crash');
            }
          }
        }

        if (kDebugMode) {
          debugPrint('Loaded ${_results.length} calendar matches from database');
          // SAFETY: Limit debug output to prevent potential crash from large datasets
          final maxDebugMatches = 10;
          final matchesToDebug = _results.take(maxDebugMatches).toList();
          for (final result in matchesToDebug) {
            debugPrint('Match: ${result.homeTeam} vs ${result.awayTeam} (${result.category}) - ${result.matchDate.day}/${result.matchDate.month} (weekday: ${result.matchDate.weekday})');
          }
          if (_results.length > maxDebugMatches) {
            debugPrint('... and ${_results.length - maxDebugMatches} more matches (debug output limited)');
          }

          // Debug specifico per weekend
          final saturdayMatches = _results.where((r) => r.matchDate.weekday == DateTime.saturday).toList();
          final sundayMatches = _results.where((r) => r.matchDate.weekday == DateTime.sunday).toList();
          debugPrint('Saturday matches: ${saturdayMatches.length}');
          debugPrint('Sunday matches: ${sundayMatches.length}');

          // Debug per categorie U18, U19, U21
          final u18Matches = _results.where((r) => r.category?.contains('U18') == true).toList();
          final u19Matches = _results.where((r) => r.category?.contains('U19') == true).toList();
          final u21Matches = _results.where((r) => r.category?.contains('U21') == true).toList();
          debugPrint('U18 matches: ${u18Matches.length}');
          debugPrint('U19 matches: ${u19Matches.length}');
          debugPrint('U21 matches: ${u21Matches.length}');
        }

        // SELENIUM API: Fast and reliable scraping via HTTP API
        if (_scrapingEnabled) {
          try {
            if (kDebugMode) {
              debugPrint('🌐 Starting Selenium API scraping...');
            }
            await _updateScoresWithSeleniumApi();
          } catch (scrapingError) {
            if (kDebugMode) {
              debugPrint('❌ Error during Selenium API scraping: $scrapingError');
              debugPrint('Continuing without scraping updates...');
            }
          }
        }

      } catch (error) {
        if (kDebugMode) {
          debugPrint('=== DATABASE CONNECTION FAILED ===');
          debugPrint('Database error: $error');
          debugPrint('USING SAMPLE DATA INSTEAD OF REAL DATABASE');
          debugPrint('This means scraping will test against sample matches, not real ones');
        }

        // Carica partite di esempio se il database non è disponibile
        _loadSampleMatches();

        if (kDebugMode) {
          debugPrint('Sample matches loaded: ${_results.length}');
          final saturdayMatches = _results.where((r) => r.matchDate.weekday == DateTime.saturday).toList();
          final sundayMatches = _results.where((r) => r.matchDate.weekday == DateTime.sunday).toList();
          debugPrint('Sample Saturday matches: ${saturdayMatches.length}');
          debugPrint('Sample Sunday matches: ${sundayMatches.length}');
          debugPrint('WARNING: These are SAMPLE matches, not real database data!');
          debugPrint('=================================');
        }
      }

      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error loading results: $error');
      }
      _setError('Errore nel caricamento dei risultati: ${error.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // Converte una partita del calendario in MatchResult con punteggio iniziale 0-0
  MatchResult _convertMatchToResult(Match match) {
    // Combina data e ora per creare DateTime completo
    final dateParts = match.time.split(':');
    final hour = dateParts.isNotEmpty ? int.tryParse(dateParts[0]) ?? 0 : 0;
    final minute = dateParts.length > 1 ? int.tryParse(dateParts[1]) ?? 0 : 0;

    final matchDateTime = DateTime(
      match.date.year,
      match.date.month,
      match.date.day,
      hour,
      minute,
    );

    // Determina squadra di casa e ospite
    final homeTeam = match.isHome ? 'AURORA SERIATE' : match.opponent;
    final awayTeam = match.isHome ? match.opponent : 'AURORA SERIATE';

    // Mappa auroraTeam a categoria standardizzata
    final category = _mapAuroraTeamToCategory(match.auroraTeam);

    // Determina i punteggi (se non ancora giocata = 0-0)
    int homeScore = 0;
    int awayScore = 0;

    // Se i goal sono stati inseriti nel calendario, usali
    if (match.goalsAurora != null && match.goalsOpponent != null) {
      if (match.isHome) {
        homeScore = match.goalsAurora!;
        awayScore = match.goalsOpponent!;
      } else {
        homeScore = match.goalsOpponent!;
        awayScore = match.goalsAurora!;
      }
    }
    // Altrimenti rimane 0-0 (partita non ancora giocata)

    return MatchResult(
      id: match.id ?? '',
      homeTeam: homeTeam,
      awayTeam: awayTeam,
      homeScore: homeScore,
      awayScore: awayScore,
      matchDate: matchDateTime,
      championship: _getChampionshipFromCategory(category),
      category: category,
      round: match.giornata != null ? 'Giornata ${match.giornata}' : null,
      venue: match.location,
    );
  }

  // Mappa il campo auroraTeam del calendario alla categoria standardizzata
  String _mapAuroraTeamToCategory(String? auroraTeam) {
    if (auroraTeam == null) {
      if (kDebugMode) {
        debugPrint('WARNING: auroraTeam is null');
      }
      return 'UNKNOWN';
    }

    final team = auroraTeam.toUpperCase();

    if (kDebugMode) {
      debugPrint('Mapping aurora_team: "$auroraTeam" -> "${team}"');
    }

    // Mappature corrette secondo i nomi reali delle categorie
    if (team.contains('U21') || team.contains('21') || team.contains('TERZA')) {
      if (kDebugMode) debugPrint('  -> Mapped to U21 TERZA');
      return 'U21 TERZA';
    }
    if (team.contains('JUNIORES') || team.contains('U19') || team.contains('ELITE')) {
      if (kDebugMode) debugPrint('  -> Mapped to U19 JUNIORES ELITE');
      return 'U19 JUNIORES ELITE';
    }
    if (team.contains('U18') || (team.contains('18') && team.contains('ALLIEVI'))) {
      if (kDebugMode) debugPrint('  -> Mapped to U18 ALLIEVI REG');
      return 'U18 ALLIEVI REG';
    }
    if (team.contains('U17') || (team.contains('17') && team.contains('ALLIEVI'))) {
      if (kDebugMode) debugPrint('  -> Mapped to U17 ALLIEVI REG');
      return 'U17 ALLIEVI REG';
    }
    if (team.contains('U16') || (team.contains('16') && team.contains('ALLIEVI'))) {
      if (kDebugMode) debugPrint('  -> Mapped to U16 ALLIEVI');
      return 'U16 ALLIEVI';
    }
    if (team.contains('U15') || (team.contains('15') && team.contains('GIOVANISSIMI'))) {
      if (kDebugMode) debugPrint('  -> Mapped to U15 GIOVANISSIMI');
      return 'U15 GIOVANISSIMI';
    }
    if (team.contains('U14') || (team.contains('14') && team.contains('GIOVANISSIMI'))) {
      if (kDebugMode) debugPrint('  -> Mapped to U14 GIOVANISSIMI');
      return 'U14 GIOVANISSIMI';
    }

    if (kDebugMode) {
      debugPrint('  -> No mapping found, returning original: $auroraTeam');
    }
    return auroraTeam; // Restituisce il valore originale se non matcha
  }

  // Ottieni il nome del campionato dalla categoria
  String _getChampionshipFromCategory(String category) {
    switch (category) {
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

  // Aggiorna i punteggi delle partite con i risultati reali da tuttocampo.it
  // NUOVO: Scraper limitato solo alle partite caricate dal database
  Future<void> _updateScoresFromTuttocampo() async {
    try {
      if (kDebugMode) {
        debugPrint('=== UPDATING SCORES FROM TUTTOCAMPO (SMART FILTERING) ===');
        debugPrint('Database matches to update: ${_results.length}');
      }

      if (_results.isEmpty) {
        if (kDebugMode) {
          debugPrint('No database matches to update');
        }
        return;
      }

      // NUOVO: Raggruppa le partite per categoria per ottimizzare lo scraping
      final matchesByCategory = <String, List<MatchResult>>{};
      for (final match in _results) {
        final category = match.category ?? _inferCategoryFromChampionship(match.championship ?? '');
        if (category != 'UNKNOWN' && _getCategoryUrlPath(category).isNotEmpty) {
          matchesByCategory[category] ??= [];
          matchesByCategory[category]!.add(match);
        }
      }

      if (kDebugMode) {
        debugPrint('=== SCRAPING ANALYSIS ===');
        debugPrint('Total matches in database: ${_results.length}');
        debugPrint('Categories to scrape: ${matchesByCategory.keys.join(', ')}');
        debugPrint('Matches by category:');
        for (final entry in matchesByCategory.entries) {
          debugPrint('  ${entry.key}: ${entry.value.length} matches');
          for (final match in entry.value) {
            debugPrint('    - ${match.homeTeam} vs ${match.awayTeam} (${match.matchDate.day}/${match.matchDate.month})');
          }
        }
        debugPrint('Expected: Only 3 specific matches from database should be processed');
        debugPrint('========================');
      }

      // Scraping per categoria invece che per singola partita
      final updatedResults = <MatchResult>[];

      for (final categoryEntry in matchesByCategory.entries) {
        final category = categoryEntry.key;
        final categoryMatches = categoryEntry.value;

        // TEMPORARY FIX: Skip problematic categories in web environment due to CORS
        if (kIsWeb && (category == 'U18 ALLIEVI REG' || category == 'U19 JUNIORES ELITE' ||
                       category == 'U16 ALLIEVI' || category == 'U14 GIOVANISSIMI' ||
                       category == 'U21 TERZA' || category == 'U17 ALLIEVI REG')) {
          if (kDebugMode) {
            debugPrint('SKIPPING category $category in web environment due to CORS restrictions');
          }
          updatedResults.addAll(categoryMatches);
          continue;
        }

        try {
          if (kDebugMode) {
            debugPrint('Scraping category $category for ${categoryMatches.length} matches');
          }

          // NUOVO: Scraping specifico per ogni partita invece di tutta la categoria
          for (final match in categoryMatches) {
            try {
              if (kDebugMode) {
                debugPrint('🎯 Searching specific match: ${match.homeTeam} vs ${match.awayTeam}');
              }

              final urlPath = _getCategoryUrlPath(category);
              // TuttocampoScraper removed - using Selenium instead
              final MatchResult? scrapedMatch = null;

              if (scrapedMatch != null && scrapedMatch.homeScore + scrapedMatch.awayScore > 0) {
                updatedResults.add(match.copyWith(
                  homeScore: scrapedMatch.homeScore,
                  awayScore: scrapedMatch.awayScore,
                ));

                if (kDebugMode) {
                  debugPrint('✅ Updated specific match: ${match.homeTeam} vs ${match.awayTeam} -> ${scrapedMatch.homeScore}-${scrapedMatch.awayScore}');
                }
              } else {
                if (kDebugMode) {
                  debugPrint('❌ No result found for: ${match.homeTeam} vs ${match.awayTeam}');
                }
                updatedResults.add(match); // Mantieni originale
              }

              // Piccola pausa tra partite per evitare rate limiting
              await Future.delayed(const Duration(milliseconds: 500));

            } catch (e) {
              if (kDebugMode) {
                debugPrint('Error scraping specific match ${match.homeTeam} vs ${match.awayTeam}: $e');
              }
              updatedResults.add(match); // Mantieni originale in caso di errore
            }
          }

          // Pausa tra categorie per evitare rate limiting
          await Future.delayed(const Duration(milliseconds: 1000));

        } catch (e) {
          if (kDebugMode) {
            debugPrint('Error scraping category $category: $e');
          }
          // Aggiungi le partite originali se lo scraping fallisce
          updatedResults.addAll(categoryMatches);
        }
      }

      // Aggiungi le partite senza categoria valida
      for (final match in _results) {
        final category = match.category ?? _inferCategoryFromChampionship(match.championship ?? '');
        if (category == 'UNKNOWN' || _getCategoryUrlPath(category).isEmpty) {
          updatedResults.add(match);
          if (kDebugMode) {
            debugPrint('Skipped match without valid category: ${match.homeTeam} vs ${match.awayTeam}');
          }
        }
      }

      _results = updatedResults;

      if (kDebugMode) {
        debugPrint('Score update completed for ${_results.length} matches (${matchesByCategory.length} categories scraped)');
      }

    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error updating scores from tuttocampo: $error');
      }
      // Non fermare l'esecuzione, mantieni le partite con punteggi 0-0
    }
  }

  // NUOVO: Scraping di una categoria una sola volta
  Future<List<MatchResult>> _scrapeCategoryOnce(String category) async {
    try {
      final urlPath = _getCategoryUrlPath(category);
      if (urlPath.isEmpty) return [];

      // TuttocampoScraper removed - using Selenium instead
      return <MatchResult>[];
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error in single category scraping for $category: $e');
      }
      return [];
    }
  }

  // NUOVO: Aggiorna una singola partita specifica da Tuttocampo
  Future<MatchResult> _updateSingleMatchFromTuttocampo(MatchResult match) async {
    try {
      // Determina la categoria per costruire l'URL specifico
      final category = match.category ?? _inferCategoryFromChampionship(match.championship ?? '');
      final urlPath = _getCategoryUrlPath(category);

      if (urlPath.isEmpty) {
        if (kDebugMode) {
          debugPrint('No URL path found for category: $category');
        }
        return match;
      }

      // Scraping specifico per questa categoria
      // TuttocampoScraper removed - using Selenium instead
      final categoryResults = <MatchResult>[];

      // Cerca la partita specifica tra i risultati
      final scrapedResult = categoryResults.firstWhere(
        (result) => _matchesPartita(match, result),
        orElse: () => match, // Ritorna la partita originale se non trovata
      );

      // Se trovato un risultato aggiornato, lo usa
      if (scrapedResult != match && scrapedResult.homeScore + scrapedResult.awayScore > 0) {
        if (kDebugMode) {
          debugPrint('Updated ${match.homeTeam} vs ${match.awayTeam}: ${scrapedResult.homeScore}-${scrapedResult.awayScore}');
        }
        return match.copyWith(
          homeScore: scrapedResult.homeScore,
          awayScore: scrapedResult.awayScore,
        );
      }

      return match;
    } catch (e) {
      if (kDebugMode) {
        debugPrint('Error updating single match: $e');
      }
      return match;
    }
  }

  // NUOVO: Mappa la categoria all'URL path
  String _getCategoryUrlPath(String category) {
    switch (category.toUpperCase()) {
      case 'PROMOZIONE':
        return '/Lombardia/Promozione/GironeA/Risultati';
      case 'U21 TERZA':
        return '/Lombardia/Under21/GironeD/Risultati';
      case 'U19 JUNIORES ELITE':
        return '/Lombardia/JunioresEliteU19/GironeC/Risultati';
      case 'U18 ALLIEVI REG':
        return '/Lombardia/AllieviRegionaliU18/GironeD/Risultati';
      case 'U17 ALLIEVI REG':
        return '/Lombardia/AllieviRegionaliU17/GironeD/Risultati';
      case 'U16 ALLIEVI':
        return '/Lombardia/AllieviProvincialiU16/GironeDBergamo/Risultati';
      case 'U15 GIOVANISSIMI':
        return '/Lombardia/GiovanissimiProvincialiU15/GironeCBergamo/Risultati';
      case 'U14 GIOVANISSIMI':
        return '/Lombardia/GiovanissimiProvincialiU14/GironeCBergamo/Risultati';
      default:
        return '';
    }
  }

  // NUOVO: Inferisce la categoria dal nome del campionato
  String _inferCategoryFromChampionship(String championship) {
    final champ = championship.toUpperCase();
    if (champ.contains('PROMOZIONE')) return 'PROMOZIONE';
    if (champ.contains('UNDER21') || champ.contains('U21') || champ.contains('TERZA')) return 'U21 TERZA';
    if (champ.contains('JUNIORES') || champ.contains('U19') || champ.contains('ELITE')) return 'U19 JUNIORES ELITE';
    if (champ.contains('U18') || (champ.contains('ALLIEVI') && champ.contains('18'))) return 'U18 ALLIEVI REG';
    if (champ.contains('U17') || (champ.contains('ALLIEVI') && champ.contains('17'))) return 'U17 ALLIEVI REG';
    if (champ.contains('U16') && champ.contains('ALLIEVI')) return 'U16 ALLIEVI';
    if (champ.contains('U15') && champ.contains('GIOVANISSIMI')) return 'U15 GIOVANISSIMI';
    if (champ.contains('U14') && champ.contains('GIOVANISSIMI')) return 'U14 GIOVANISSIMI';
    return 'UNKNOWN';
  }

  // Verifica se una partita del database corrisponde a un risultato di tuttocampo.it
  bool _matchesPartita(MatchResult dbMatch, MatchResult scrapedResult) {
    // Confronta squadre e data (stesso giorno)
    final sameDay = dbMatch.matchDate.year == scrapedResult.matchDate.year &&
                   dbMatch.matchDate.month == scrapedResult.matchDate.month &&
                   dbMatch.matchDate.day == scrapedResult.matchDate.day;

    final sameTeams = (dbMatch.homeTeam.toLowerCase().contains('aurora') &&
                      scrapedResult.homeTeam.toLowerCase().contains('aurora') &&
                      _similarTeamNames(dbMatch.awayTeam, scrapedResult.awayTeam)) ||
                     (dbMatch.awayTeam.toLowerCase().contains('aurora') &&
                      scrapedResult.awayTeam.toLowerCase().contains('aurora') &&
                      _similarTeamNames(dbMatch.homeTeam, scrapedResult.homeTeam));

    return sameDay && sameTeams;
  }

  // Verifica se due nomi di squadra sono simili
  bool _similarTeamNames(String name1, String name2) {
    final clean1 = name1.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');
    final clean2 = name2.toLowerCase().replaceAll(RegExp(r'[^a-z]'), '');

    // Controllo di somiglianza semplice
    return clean1.contains(clean2) || clean2.contains(clean1) || clean1 == clean2;
  }

  // Metodo per caricare partite di esempio - SOLO CALENDARIO, RISULTATI 0-0
  void _loadSampleMatches() {
    final now = DateTime.now();

    _results = [
      // SABATO - ORDINE CRONOLOGICO

      // U18 REGIONALE - Sabato ore 15:00 - PARTITA PROGRAMMATA
      MatchResult(
        id: '1',
        homeTeam: 'SCANZOROSCIATE',
        awayTeam: 'AURORA SERIATE',
        homeScore: 0, // Non ancora giocata
        awayScore: 0, // Non ancora giocata
        matchDate: DateTime(now.year, now.month, now.day - (now.weekday - DateTime.saturday), 15, 0), // Sabato 15:00
        championship: 'Allievi Regionali U18 Girone D',
        category: 'U18 ALLIEVI REG', // Corretto per lo scraping
        round: 'Giornata 3',
        venue: 'Campo Scanzorosciate',
      ),

      // U21 TERZA (Under21 Girone D) - Sabato ore 16:30 - PARTITA PROGRAMMATA
      MatchResult(
        id: '2',
        homeTeam: 'AURORA SERIATE',
        awayTeam: 'PONTE SAN PIETRO',
        homeScore: 0, // Non ancora giocata
        awayScore: 0, // Non ancora giocata
        matchDate: DateTime(now.year, now.month, now.day - (now.weekday - DateTime.saturday), 16, 30), // Sabato 16:30
        championship: 'Under21 Girone D',
        category: 'U21 TERZA', // Corretto per lo scraping
        round: 'Giornata 3',
        venue: 'Campo Comunale Aurora',
      ),

      // DOMENICA - ORDINE CRONOLOGICO

      // U19 JUNIORES ELITE - Domenica ore 10:30 - PARTITA PROGRAMMATA
      MatchResult(
        id: '3',
        homeTeam: 'CARAVAGGIO',
        awayTeam: 'AURORA SERIATE',
        homeScore: 0, // Non ancora giocata
        awayScore: 0, // Non ancora giocata
        matchDate: DateTime(now.year, now.month, now.day - (now.weekday - DateTime.sunday), 10, 30), // Domenica 10:30
        championship: 'Juniores Elite U19 Girone C',
        category: 'U19 JUNIORES ELITE', // Corretto per lo scraping
        round: 'Giornata 3',
        venue: 'Campo Sportivo Caravaggio',
      ),

      // U17 ALLIEVI REGIONALI - Domenica ore 15:00 - PARTITA PROGRAMMATA
      MatchResult(
        id: '4',
        homeTeam: 'AURORA SERIATE',
        awayTeam: 'TRITIUM',
        homeScore: 0, // Non ancora giocata
        awayScore: 0, // Non ancora giocata
        matchDate: DateTime(now.year, now.month, now.day - (now.weekday - DateTime.sunday), 15, 0), // Domenica 15:00
        championship: 'Allievi Regionali U17 Girone D',
        category: 'U17 ALLIEVI REG', // Corretto per lo scraping
        round: 'Giornata 3',
        venue: 'Campo Comunale Aurora',
      ),

      // U15 GIOVANISSIMI - Sabato ore 14:00 - PARTITA PROGRAMMATA
      MatchResult(
        id: '5',
        homeTeam: 'LEMINE ALMENNO',
        awayTeam: 'AURORA SERIATE',
        homeScore: 0,
        awayScore: 0,
        matchDate: DateTime(now.year, now.month, now.day - (now.weekday - DateTime.saturday), 14, 0), // Sabato 14:00
        championship: 'Giovanissimi Provinciali U15 Girone C Bergamo',
        category: 'U15 GIOVANISSIMI', // Corretto per lo scraping
        round: 'Giornata 3',
        venue: 'Campo Lemine Almenno',
      ),

      // U14 GIOVANISSIMI - Domenica ore 16:30 - PARTITA PROGRAMMATA
      MatchResult(
        id: '6',
        homeTeam: 'AURORA SERIATE',
        awayTeam: 'VIRTUS CISERANO',
        homeScore: 0,
        awayScore: 0,
        matchDate: DateTime(now.year, now.month, now.day - (now.weekday - DateTime.sunday), 16, 30), // Domenica 16:30
        championship: 'Giovanissimi Provinciali U14 Girone C Bergamo',
        category: 'U14 GIOVANISSIMI', // Corretto per lo scraping
        round: 'Giornata 3',
        venue: 'Campo Comunale Aurora',
      ),
    ];

    // Ordina per data e orario
    _results.sort((a, b) => a.matchDate.compareTo(b.matchDate));

    if (kDebugMode) {
      debugPrint('Loaded ${_results.length} sample results');
    }
  }

  // Filtra risultati per giorno della settimana
  List<MatchResult> getResultsByDay(String day) {
    return _results.where((result) {
      final matchDay = _getItalianDayName(result.matchDate.weekday);
      return matchDay.toLowerCase() == day.toLowerCase();
    }).toList();
  }

  // Filtra risultati del weekend (Sabato e Domenica)
  List<MatchResult> getWeekendResults() {
    return _results.where((result) {
      final weekday = result.matchDate.weekday;
      return weekday == DateTime.saturday || weekday == DateTime.sunday;
    }).toList();
  }

  // Filtra risultati per squadra specifica (es. U21, U19, ecc.)
  List<MatchResult> getResultsByTeam(String team) {
    return _results.where((result) =>
      result.homeTeam.toLowerCase().contains(team.toLowerCase()) ||
      result.awayTeam.toLowerCase().contains(team.toLowerCase())
    ).toList();
  }

  String _getItalianDayName(int weekday) {
    switch (weekday) {
      case DateTime.monday: return 'Lunedì';
      case DateTime.tuesday: return 'Martedì';
      case DateTime.wednesday: return 'Mercoledì';
      case DateTime.thursday: return 'Giovedì';
      case DateTime.friday: return 'Venerdì';
      case DateTime.saturday: return 'Sabato';
      case DateTime.sunday: return 'Domenica';
      default: return 'Sconosciuto';
    }
  }

  void _setLoading(bool loading) {
    _isLoading = loading;
    notifyListeners();
  }

  void _setError(String error) {
    _errorMessage = error;
    notifyListeners();
  }

  void _clearError() {
    _errorMessage = null;
    notifyListeners();
  }

  // Metodo per aggiungere risultati manualmente (temporaneo)
  Future<bool> addResult(MatchResult result) async {
    try {
      _setLoading(true);
      _clearError();

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato');
      }

      final resultData = result.copyWith(userId: user.id);

      try {
        final response = await _supabase
            .from('match_results')
            .insert(resultData.toJson())
            .select()
            .single();

        final newResult = MatchResult.fromJson(response);
        _results.add(newResult);
      } catch (supabaseError) {
        // Fallback: salva solo in memoria locale
        final newResult = result.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        _results.add(newResult);
      }

      _results.sort((a, b) => b.matchDate.compareTo(a.matchDate));
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta del risultato: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Metodo per caricare risultati tramite web scraping (non più usato direttamente)
  Future<void> _loadResultsFromWebScraping() async {
    try {
      if (kDebugMode) {
        debugPrint('=== STARTING WEB SCRAPING ===');
      }

      // Carica prima le partite di esempio (calendario)
      _loadSampleMatches();

      // Check safe mode for scraping
      if (_scrapingEnabled) {
        try {
          await _updateScoresFromTuttocampo();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Scraping error: $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('✅ TUTTOCAMPO SCRAPING ATTIVO - Trying to fetch live scores...');
        }
      }

    } catch (error) {
      if (kDebugMode) {
        debugPrint('Web scraping error: $error');
        debugPrint('Falling back to sample matches only');
      }
      _loadSampleMatches();
    }
  }

  Future<void> fetchResultsFromWeb() async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== MANUAL SCORE UPDATE FROM TUTTOCAMPO ===');
      }

      // Se non ci sono partite caricate, carica prima dal database
      if (_results.isEmpty) {
        await loadResults();
        return;
      }

      // Check safe mode for scraping
      if (_scrapingEnabled) {
        try {
          await _updateScoresFromTuttocampo();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Scraping error: $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('✅ TUTTOCAMPO SCRAPING ATTIVO - Trying to fetch live scores...');
        }
      }
      notifyListeners();

    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error in manual score update: $error');
      }
      _setError('⚠️ Tuttocampo.it blocca le richieste automatiche. I risultati devono essere inseriti manualmente usando il pulsante +');
    } finally {
      _setLoading(false);
    }
  }

  // NUOVO: Metodo per filtrare e aggiornare solo risultati del weekend specifico
  Future<void> fetchWeekendResults({required String day, DateTime? weekStart}) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== FETCHING $day RESULTS ===');
      }

      // Se non ci sono partite caricate, carica prima dal database
      if (_results.isEmpty) {
        await loadResults(weekStart: weekStart);
      }

      // Filtra solo le partite del giorno richiesto dal database Supabase
      final filteredResults = _results.where((result) {
        if (day.toLowerCase() == 'sabato') {
          return result.matchDate.weekday == DateTime.saturday;
        } else if (day.toLowerCase() == 'domenica') {
          return result.matchDate.weekday == DateTime.sunday;
        }
        return false;
      }).toList();

      if (kDebugMode) {
        debugPrint('Filtered ${filteredResults.length} matches for $day from database');
        for (final match in filteredResults) {
          debugPrint('  ${match.category}: ${match.homeTeam} vs ${match.awayTeam}');
        }
      }

      if (filteredResults.isEmpty) {
        if (kDebugMode) {
          debugPrint('No matches found for $day in database');
        }
        return;
      }

      // IMPORTANTE: Identifica le categorie uniche delle partite del giorno
      final categoriesForDay = filteredResults
          .map((match) => match.category ?? _inferCategoryFromChampionship(match.championship ?? ''))
          .where((category) => category != 'UNKNOWN' && _getCategoryUrlPath(category).isNotEmpty)
          .toSet()
          .toList();

      if (kDebugMode) {
        debugPrint('=== WEEKEND FILTERING FOR $day ===');
        debugPrint('Total matches available: ${_results.length}');
        debugPrint('Filtered matches for $day: ${filteredResults.length}');
        debugPrint('Categories to scrape for $day: ${categoriesForDay.join(', ')}');

        if (filteredResults.length > 3) {
          debugPrint('WARNING: More than 3 matches found! Expected only 3 specific matches.');
          debugPrint('This suggests we are loading more data than expected from database.');
        }

        debugPrint('Specific matches for $day:');
        for (final match in filteredResults) {
          debugPrint('  - ${match.homeTeam} vs ${match.awayTeam} (${match.category}) at ${match.matchDate}');
        }
        debugPrint('================================');
      }

      // Temporaneamente imposta solo le partite del giorno per lo scraping
      final originalResults = _results;
      _results = filteredResults;

      if (kDebugMode) {
        debugPrint('BEFORE SCRAPING: _results contains ${_results.length} matches');
        debugPrint('BEFORE SCRAPING: originalResults contains ${originalResults.length} matches');
      }

      // Check safe mode for scraping
      if (_scrapingEnabled) {
        try {
          await _updateScoresFromTuttocampo();
        } catch (e) {
          if (kDebugMode) {
            debugPrint('Scraping error: $e');
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('✅ TUTTOCAMPO SCRAPING ATTIVO - Trying to fetch live scores...');
        }
      }

      if (kDebugMode) {
        debugPrint('AFTER SCRAPING: _results contains ${_results.length} matches');
      }

      // Rimetti i risultati originali aggiornati
      final updatedDayResults = Map.fromEntries(
        _results.map((r) => MapEntry(r.id, r))
      );

      _results = originalResults.map((result) {
        return updatedDayResults[result.id] ?? result;
      }).toList();

      notifyListeners();

    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error in weekend results update: $error');
      }
      _setError('Errore nell\'aggiornamento risultati $day: ${error.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  // NUOVO: Metodo per aggiornare manualmente il punteggio di una partita specifica
  Future<bool> updateMatchScore(String matchId, int homeScore, int awayScore) async {
    try {
      final matchIndex = _results.indexWhere((match) => match.id == matchId);
      if (matchIndex == -1) {
        if (kDebugMode) {
          debugPrint('Match not found: $matchId');
        }
        return false;
      }

      final match = _results[matchIndex];
      final isAuroraHome = match.homeTeam.toLowerCase().contains('aurora');

      if (kDebugMode) {
        debugPrint('=== DEBUG GOAL UPDATE ===');
        debugPrint('Match: ${match.homeTeam} vs ${match.awayTeam}');
        debugPrint('Aurora is home: $isAuroraHome');
        debugPrint('Input homeScore: $homeScore, awayScore: $awayScore');
        debugPrint('Will save goals_aurora: ${isAuroraHome ? homeScore : awayScore}');
        debugPrint('Will save goals_opponent: ${isAuroraHome ? awayScore : homeScore}');
      }

      // Aggiorna il punteggio localmente
      _results[matchIndex] = _results[matchIndex].copyWith(
        homeScore: homeScore,
        awayScore: awayScore,
      );

      // Tenta di salvare nel database se possibile
      try {
        await _supabase
            .from('matches')
            .update({
              'goals_aurora': isAuroraHome ? homeScore : awayScore,
              'goals_opponent': isAuroraHome ? awayScore : homeScore,
            })
            .eq('id', matchId);

        if (kDebugMode) {
          debugPrint('Score updated in database for match $matchId');
        }
      } catch (dbError) {
        if (kDebugMode) {
          debugPrint('Failed to update database, keeping local change: $dbError');
        }
        // Non fallire se il database non è disponibile, mantieni la modifica locale
      }

      notifyListeners();
      return true;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error updating match score: $error');
      }
      return false;
    }
  }

  /// TEST SPECIFICO per U21 TERZA - sabato 27/09
  Future<void> testU21Scraping() async {
    try {
      if (kDebugMode) {
        debugPrint('=== INIZIO TEST U21 SCRAPING ===');
        debugPrint('Data test: Sabato 27/09');
        debugPrint('Categoria: U21 TERZA');
        debugPrint('URL specifico: https://www.tuttocampo.it/Lombardia/Under21/GironeD/Partita/3.2/aurora-seriate-1967-virescit');
        debugPrint('Partita attesa dal database: AURORA SERIATE vs PONTE SAN PIETRO');
        debugPrint('Partita potenziale su tuttocampo: AURORA SERIATE vs VIRESCIT');
      }

      // Filtra solo la partita U21 di sabato
      final u21Match = _results.firstWhere(
        (match) => match.category == 'U21 TERZA' &&
                   match.matchDate.weekday == DateTime.saturday,
        orElse: () => throw Exception('Partita U21 di sabato non trovata nel database'),
      );

      if (kDebugMode) {
        debugPrint('✅ Partita U21 trovata nel database:');
        debugPrint('  ${u21Match.homeTeam} vs ${u21Match.awayTeam}');
        debugPrint('  Data: ${u21Match.matchDate}');
        debugPrint('  Punteggio attuale: ${u21Match.homeScore}-${u21Match.awayScore}');
        debugPrint('  ID: ${u21Match.id}');
      }

      // PRIMA: Test diretto dell'URL specifico
      // TuttocampoScraper removed - using Selenium instead
      if (kDebugMode) {
        debugPrint('U21 testing disabled - using Selenium instead');
      }
      final scrapedResults = <MatchResult>[];

      if (scrapedResults.isNotEmpty) {
        if (kDebugMode) {
          debugPrint('✅ SCRAPING U21 RIUSCITO!');
          debugPrint('Risultati trovati: ${scrapedResults.length}');

          for (final result in scrapedResults) {
            debugPrint('Risultato scraping:');
            debugPrint('  ${result.homeTeam} vs ${result.awayTeam}');
            debugPrint('  Punteggio: ${result.homeScore}-${result.awayScore}');

            // Verifica se corrisponde alla partita nel database
            // Logica più flessibile per U21 che considera nomi squadra diversi
            final isAuroraMatch = (result.homeTeam.toLowerCase().contains('aurora') ||
                                  result.awayTeam.toLowerCase().contains('aurora'));
            final matchesDatabase = _matchesPartita(u21Match, result);

            if (matchesDatabase || isAuroraMatch) {
              if (matchesDatabase) {
                debugPrint('  ✅ PERFECT MATCH! Corrisponde esattamente alla partita nel database');
              } else {
                debugPrint('  ⚠️ PARTIAL MATCH! Partita Aurora trovata ma nomi squadre diversi:');
                debugPrint('    Database: ${u21Match.homeTeam} vs ${u21Match.awayTeam}');
                debugPrint('    Tuttocampo: ${result.homeTeam} vs ${result.awayTeam}');
                debugPrint('    Probabilmente la stessa partita con nomi diversi');
              }

              // Aggiorna il punteggio se diverso da 0-0
              if (result.homeScore > 0 || result.awayScore > 0) {
                final success = await updateMatchScore(
                  u21Match.id!,
                  result.homeScore,
                  result.awayScore
                );

                if (success) {
                  debugPrint('  ✅ Punteggio aggiornato nel database!');
                } else {
                  debugPrint('  ❌ Errore aggiornamento database');
                }
              } else {
                debugPrint('  ℹ️ Punteggio ancora 0-0 su tuttocampo');
              }
            } else {
              debugPrint('  ❌ Non corrisponde alla partita nel database');
            }
          }
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ SCRAPING U21 FALLITO');
          debugPrint('Nessun risultato trovato da tuttocampo.it');
          debugPrint('Verifica:');
          debugPrint('  1. URL funzionanti per U21');
          debugPrint('  2. Partita pubblicata sui risultati');
          debugPrint('  3. Blocchi di tuttocampo.it');
        }
      }

    } catch (error) {
      if (kDebugMode) {
        debugPrint('❌ ERRORE TEST U21: $error');
      }
    }
  }

  /// SELENIUM API: Simple and fast scraping method for all categories via HTTP API
  Future<void> _updateScoresWithSeleniumApi() async {
    try {
      if (kDebugMode) {
        debugPrint('🌐 Starting single Selenium API scraping for AURORA SERIATE results...');
        debugPrint('📋 Total agonistic matches to update: ${_results.length}');
      }

      if (_results.isEmpty) {
        if (kDebugMode) {
          debugPrint('❌ No agonistic matches found for Saturday - skipping scraping');
        }
        return;
      }

      // Fai UN SOLO scraping per "AURORA SERIATE" che trova TUTTE le partite del giorno
      try {
        if (kDebugMode) {
          debugPrint('🎯 Scraping ALL Aurora results from tuttocampo using single search...');
        }

        // Nuovo approccio: scraping generale di AURORA SERIATE (non per categoria)
        final allAuroraResults = await _scrapeAllAuroraResultsForDay();

        if (allAuroraResults.isNotEmpty) {
          if (kDebugMode) {
            debugPrint('✅ Found ${allAuroraResults.length} Aurora results from tuttocampo:');
            for (final result in allAuroraResults) {
              debugPrint('   ${result.homeTeam} ${result.homeScore}-${result.awayScore} ${result.awayTeam} (${result.category})');
            }
          }

          // Aggiorna le partite del database con i risultati trovati
          for (int i = 0; i < _results.length; i++) {
            final dbMatch = _results[i];

            // Trova il risultato corrispondente dalla lista
            MatchResult? scrapedResult;
            try {
              scrapedResult = allAuroraResults.firstWhere(
                (scraped) => _isMatchingSemantic(dbMatch, scraped),
              );
            } catch (e) {
              scrapedResult = null;
            }

            if (scrapedResult != null) {
              _results[i] = dbMatch.copyWith(
                homeScore: scrapedResult.homeScore,
                awayScore: scrapedResult.awayScore,
              );

              if (kDebugMode) {
                debugPrint('✅ Updated match: ${scrapedResult.homeTeam} ${scrapedResult.homeScore}-${scrapedResult.awayScore} ${scrapedResult.awayTeam}');
              }
            }
          }
        } else {
          if (kDebugMode) {
            debugPrint('❌ No Aurora results found on tuttocampo for today');
          }
        }

      } catch (scrapingError) {
        if (kDebugMode) {
          debugPrint('❌ Error scraping Aurora results: $scrapingError');
        }
      }

    } catch (error) {
      if (kDebugMode) {
        debugPrint('❌ Error in Selenium API scraping: $error');
      }
    }
  }

  /// Check if a database match corresponds to a scraped result
  bool _isMatchingSemantic(MatchResult dbMatch, MatchResult scrapedResult) {
    // Both should involve Aurora
    final dbHasAurora = dbMatch.homeTeam.toLowerCase().contains('aurora') ||
                       dbMatch.awayTeam.toLowerCase().contains('aurora');
    final scrapedHasAurora = scrapedResult.homeTeam.toLowerCase().contains('aurora') ||
                            scrapedResult.awayTeam.toLowerCase().contains('aurora');

    if (!dbHasAurora || !scrapedHasAurora) return false;

    // Check if they share an opponent (basic similarity)
    final dbOpponent = dbMatch.homeTeam.toLowerCase().contains('aurora') ?
                      dbMatch.awayTeam.toLowerCase() : dbMatch.homeTeam.toLowerCase();
    final scrapedOpponent = scrapedResult.homeTeam.toLowerCase().contains('aurora') ?
                           scrapedResult.awayTeam.toLowerCase() : scrapedResult.homeTeam.toLowerCase();

    // Simple word matching for opponent names
    final dbWords = dbOpponent.split(' ').where((w) => w.length > 2).toSet();
    final scrapedWords = scrapedOpponent.split(' ').where((w) => w.length > 2).toSet();

    return dbWords.intersection(scrapedWords).isNotEmpty;
  }

  // Pulisce il nome della categoria per confronti
  String _cleanCategoryName(String? category) {
    if (category == null) return '';

    final cleanCategory = category.toUpperCase()
        .replaceAll(' ALLIEVI REG', '')
        .replaceAll(' ALLIEVI', '')
        .replaceAll(' JUNIORES ELITE', '')
        .replaceAll(' JUNIORES', '')
        .replaceAll(' GIOVANISSIMI', '')
        .replaceAll(' TERZA', '')
        .replaceAll(' REG', '')
        .replaceAll(' ELITE', '')
        .trim();

    if (kDebugMode) {
      debugPrint('🧹 ResultsService - Categoria originale: "$category" → pulita: "$cleanCategory"');
    }

    return cleanCategory;
  }

  /// Nuovo metodo: scarica TUTTI i risultati Aurora del giorno usando l'endpoint ottimizzato
  Future<List<MatchResult>> _scrapeAllAuroraResultsForDay() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Inizio discovery automatica del server selenium...');
      }

      // Discovery automatica: prova prima Render, poi rete locale
      final List<String> serverUrls = [
        'https://aurora-selenium-api.onrender.com', // Server Render principale (aggiornato)
        'https://aurora-selenium-api2.onrender.com', // Server Render secondario
        'http://192.168.1.13:5001', // Rete locale di casa
        'http://10.0.2.2:5001', // Android emulator localhost
        'http://localhost:5001', // Locale diretto
      ];

      String? workingServerUrl;

      // Testa ogni server per trovare quello funzionante
      for (final url in serverUrls) {
        try {
          if (kDebugMode) {
            debugPrint('🔍 Testando server: $url/health');
          }

          final healthResponse = await http.get(
            Uri.parse('$url/health'),
          ).timeout(const Duration(seconds: 8));

          if (healthResponse.statusCode == 200) {
            workingServerUrl = url;
            if (kDebugMode) {
              debugPrint('✅ Server attivo trovato: $url');
            }
            break;
          } else {
            if (kDebugMode) {
              debugPrint('❌ $url non raggiungibile: HTTP ${healthResponse.statusCode}');
            }
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('❌ $url non raggiungibile: $e');
          }
        }
      }

      if (workingServerUrl == null) {
        if (kDebugMode) {
          debugPrint('❌ Nessun server selenium trovato sui IP testati');
        }
        return [];
      }

      if (kDebugMode) {
        debugPrint('🎯 Usando server Selenium: $workingServerUrl');
      }

      // Chiama il nuovo endpoint per tutti i risultati Aurora
      final response = await http.get(
        Uri.parse('$workingServerUrl/scrape/aurora-results'),
      ).timeout(const Duration(seconds: 60)); // Timeout più lungo per scraping completo

      if (kDebugMode) {
        debugPrint('Aurora results API Response Status: ${response.statusCode}');
        debugPrint('Aurora results API Response Body: ${response.body}');
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);

        if (data['success'] == true && data['data'] != null) {
          final resultsData = data['data'] as List;

          List<MatchResult> allResults = [];

          for (final resultData in resultsData) {
            try {
              final matchResult = MatchResult(
                id: 'aurora_${resultData['category']?.toLowerCase() ?? 'unknown'}_${DateTime.now().millisecondsSinceEpoch}',
                homeTeam: resultData['homeTeam'] ?? '',
                awayTeam: resultData['awayTeam'] ?? '',
                homeScore: resultData['homeScore'] ?? 0,
                awayScore: resultData['awayScore'] ?? 0,
                matchDate: DateTime.now(),
                category: resultData['category'] ?? '',
                championship: resultData['championship'] ?? '',
              );

              allResults.add(matchResult);

              if (kDebugMode) {
                debugPrint('✅ Parsed result: ${matchResult.homeTeam} ${matchResult.homeScore}-${matchResult.awayScore} ${matchResult.awayTeam}');
              }
            } catch (parseError) {
              if (kDebugMode) {
                debugPrint('❌ Error parsing result: $parseError');
              }
            }
          }

          return allResults;
        } else {
          if (kDebugMode) {
            debugPrint('❌ API returned no Aurora results for today');
          }
          return [];
        }
      } else {
        if (kDebugMode) {
          debugPrint('❌ Aurora results API request failed with status: ${response.statusCode}');
          debugPrint('Error response: ${response.body}');
        }
        return [];
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error calling Aurora results API: $e');
      }
      return [];
    }
  }

  // Metodo per aggiornare le posizioni di Aurora nelle card
  void updateAuroraPosition(String category, int position) {
    final cleanApiCategory = category.toUpperCase();

    for (int i = 0; i < _results.length; i++) {
      final result = _results[i];
      final cleanResultCategory = _cleanCategoryName(result.category);

      if (cleanResultCategory == cleanApiCategory) {
        final isAuroraHome = result.homeTeam.toLowerCase().contains('aurora');
        final isAuroraAway = result.awayTeam.toLowerCase().contains('aurora');

        if (isAuroraHome) {
          _results[i] = result.copyWith(homePosition: position);
        } else if (isAuroraAway) {
          _results[i] = result.copyWith(awayPosition: position);
        }
      }
    }
    notifyListeners();
  }

  // Metodo per aggiornare le posizioni di qualsiasi squadra nelle card
  void updateTeamPosition(String category, String teamName, int position) {
    final cleanApiCategory = category.toUpperCase();
    final searchTeamName = teamName.toLowerCase();

    for (int i = 0; i < _results.length; i++) {
      final result = _results[i];
      final cleanResultCategory = _cleanCategoryName(result.category);

      if (cleanResultCategory == cleanApiCategory) {
        final homeTeamMatches = result.homeTeam.toLowerCase().contains(searchTeamName) ||
                               searchTeamName.contains(result.homeTeam.toLowerCase()) ||
                               _teamNamesMatch(result.homeTeam, teamName);

        final awayTeamMatches = result.awayTeam.toLowerCase().contains(searchTeamName) ||
                               searchTeamName.contains(result.awayTeam.toLowerCase()) ||
                               _teamNamesMatch(result.awayTeam, teamName);

        if (homeTeamMatches) {
          _results[i] = result.copyWith(homePosition: position);
        } else if (awayTeamMatches) {
          _results[i] = result.copyWith(awayPosition: position);
        }
      }
    }
    notifyListeners();
  }

  // Helper per confrontare nomi squadre con variazioni
  bool _teamNamesMatch(String name1, String name2) {
    final clean1 = name1.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    final clean2 = name2.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');

    // Match se uno contiene l'altro o sono simili
    return clean1.contains(clean2) || clean2.contains(clean1) ||
           clean1.split(' ').any((word) => clean2.contains(word)) ||
           clean2.split(' ').any((word) => clean1.contains(word));
  }
}