import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'dart:io';
import '../services/results_service.dart';
import '../services/live_match_monitor.dart';
import '../models/result_model.dart';
import '../widgets/manual_score_dialog.dart';
import '../widgets/fast_team_logo.dart';

class ResultsScreen extends StatefulWidget {
  final String title;
  final DateTime? weekStart; // Settimana specifica da mostrare

  const ResultsScreen({
    super.key,
    this.title = 'Risultati',
    this.weekStart, // Opzionale
  });

  @override
  State<ResultsScreen> createState() => _ResultsScreenState();
}

class _ResultsScreenState extends State<ResultsScreen> {
  DateTime _currentWeekStart = DateTime.now();
  DateTime _currentDate = DateTime.now();

  // Modalità visualizzazione classifica
  bool _isStandingsMode = false;
  MatchResult? _selectedMatch;
  Map<String, dynamic>? _currentStandings;

  // Server discovery automatico
  String? _serverBaseUrl;
  static const List<String> _possibleIPs = [
    '10.14.0.2:5001',    // Current server IP
    '10.0.2.2:5001',     // Android emulator standard
    '172.20.10.3:5001',  // iPhone hotspot common IP
    '192.168.1.100:5001', // Home network common IP
    '192.168.0.100:5001', // Alternative home network
    'localhost:5001',    // Web/Desktop fallback
  ];

  @override
  void initState() {
    super.initState();

    // Imposta la settimana dal widget o quella attuale
    if (widget.weekStart != null) {
      _currentWeekStart = widget.weekStart!;
      _currentDate = widget.weekStart!;
    } else {
      final now = DateTime.now();
      _currentWeekStart = _getWeekStart(now);
      _currentDate = now;
    }

    // Carica i risultati quando la schermata viene inizializzata
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final resultsService = context.read<ResultsService>();
      if (kDebugMode) {
        debugPrint('=== RESULTS SCREEN INIT ===');
        debugPrint('Results count: ${resultsService.results.length}');
        debugPrint('Is loading: ${resultsService.isLoading}');
        debugPrint('Error: ${resultsService.errorMessage}');
      }

      // Forza sempre il caricamento per la settimana corrente
      resultsService.loadResults(weekStart: _currentDate).then((_) {
        // Dopo aver caricato i risultati, carica le posizioni per Aurora agonistiche
        if (kDebugMode) {
          print('🔄 Risultati caricati, avvio caricamento posizioni Aurora...');
        }
        _loadPositionsForAuroraMatches().catchError((error) {
          if (kDebugMode) {
            print('❌ Errore caricamento posizioni automatico: $error');
          }
        });
      }).catchError((error) {
        if (kDebugMode) {
          print('❌ Errore caricamento risultati: $error');
        }
      });

      // Avvia il monitoraggio automatico durante i weekend
      final liveMonitor = context.read<LiveMatchMonitor>();
      liveMonitor.startWeekendMonitoring();
    });
  }

  // Determina se una categoria è agonistica (tutte le squadre Aurora)
  bool _isAgonisticCategory(String? category) {
    if (category == null) return false;
    final cat = category.toUpperCase();
    return cat.contains('PROMOZIONE') ||
           cat.contains('U21') ||
           cat.contains('U19') ||
           cat.contains('U18') ||
           cat.contains('U17') ||
           cat.contains('U16') ||
           cat.contains('U15') ||
           cat.contains('U14');
  }

  // Pulisce il nome della categoria per l'API (rimuove ALLIEVI, JUNIORES, ecc.)
  String? _cleanCategoryName(String? category) {
    if (category == null) return null;

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
      print('🧹 Categoria originale: "$category" → pulita: "$cleanCategory"');
    }

    return cleanCategory;
  }

  // Carica automaticamente le posizioni per tutte le squadre Aurora agonistiche
  Future<void> _loadPositionsForAuroraMatches() async {
    if (kDebugMode) {
      print('🔄 Caricamento automatico posizioni Aurora...');
    }

    final resultsService = context.read<ResultsService>();

    if (kDebugMode) {
      print('📋 Totale risultati disponibili: ${resultsService.results.length}');
    }

    // Filtra solo le partite Aurora agonistiche del giorno corrente
    final currentDayResults = _getFilteredResults(resultsService);

    if (kDebugMode) {
      print('📅 Risultati del giorno corrente: ${currentDayResults.length}');
    }

    final auroraMatches = currentDayResults.where((result) {
      final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                           result.awayTeam.toLowerCase().contains('aurora');
      final isAgonistic = _isAgonisticCategory(result.category);

      if (kDebugMode && isAuroraMatch) {
        print('🔍 Aurora match trovato: ${result.category} - Agonistica: $isAgonistic');
      }

      return isAuroraMatch && isAgonistic;
    }).toList();

    if (kDebugMode) {
      print('⚽ Partite Aurora agonistiche oggi: ${auroraMatches.length}');
      for (var match in auroraMatches) {
        print('  - ${match.homeTeam} vs ${match.awayTeam} (${match.category})');
      }
    }

    if (auroraMatches.isEmpty) {
      if (kDebugMode) {
        print('ℹ️ Nessuna partita Aurora agonistica oggi');
      }
      return;
    }

    // Carica posizioni per ciascuna categoria Aurora agonistica presente oggi
    final categoriesProcessed = <String>{};
    for (final match in auroraMatches) {
      final cleanCategory = _cleanCategoryName(match.category);
      if (cleanCategory != null && !categoriesProcessed.contains(cleanCategory)) {
        categoriesProcessed.add(cleanCategory);

        if (kDebugMode) {
          print('📊 Caricamento posizione per Aurora $cleanCategory...');
        }

        await _loadStandingsForCategory(cleanCategory);
      }
    }

    if (kDebugMode) {
      print('✅ Caricamento posizioni completato per ${categoriesProcessed.length} categorie');
    }
  }

  // Carica la classifica per una categoria e aggiorna le posizioni nel database
  Future<void> _loadStandingsForCategory(String category) async {
    try {
      if (kDebugMode) {
        print('🔄 Caricamento posizioni per $category...');
      }

      final serverUrl = await _discoverServerUrl();
      if (serverUrl == null) {
        if (kDebugMode) {
          print('❌ Server selenium non trovato per $category');
        }
        _setFallbackPosition(category);
        return;
      }

      final response = await http.get(
        Uri.parse('$serverUrl/standings/$category'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['success'] == true && data['standings'] != null) {
          final standings = data['standings'] as Map<String, dynamic>;

          // Aggiorna le posizioni di tutte le squadre nel ResultsService
          final resultsService = context.read<ResultsService>();

          for (final teamKey in standings.keys) {
            final position = standings[teamKey]['position'] as int;
            final teamName = standings[teamKey]['team_name'] as String;

            if (teamKey.toLowerCase().contains('aurora')) {
              // Usa il metodo specifico per Aurora per compatibilità
              resultsService.updateAuroraPosition(category, position);
              if (kDebugMode) {
                print('✅ Aurora $category: ${position}° posizione aggiornata in UI');
              }
            } else {
              // Usa il nuovo metodo per tutte le altre squadre
              resultsService.updateTeamPosition(category, teamName, position);
              if (kDebugMode) {
                print('✅ $teamName $category: ${position}° posizione aggiornata in UI');
              }
            }
          }
        }
      } else {
        if (kDebugMode) {
          print('⚠️ Errore API posizioni $category: ${response.statusCode}');
        }
        // Fallback: imposta posizione placeholder quando l'API fallisce
        _setFallbackPosition(category);
      }
    } catch (e) {
      if (kDebugMode) {
        print('⚠️ Errore caricamento posizioni $category: $e');
      }
      // Fallback: imposta posizione placeholder quando c'è un timeout/errore
      _setFallbackPosition(category);
    }
  }

  // Imposta una posizione fallback quando il caricamento fallisce
  void _setFallbackPosition(String category) {
    final resultsService = context.read<ResultsService>();
    // Usa posizione 99 per indicare errore di caricamento, così l'UI non resta bloccata
    resultsService.updateAuroraPosition(category, 99);

    if (kDebugMode) {
      print('🔄 Posizione fallback impostata per $category (errore rete)');
    }
  }

  // Scopre automaticamente l'IP del server selenium provando diversi indirizzi
  Future<String?> _discoverServerUrl() async {
    if (_serverBaseUrl != null) {
      if (kDebugMode) {
        print('🎯 Server già scoperto: $_serverBaseUrl');
      }
      return _serverBaseUrl;
    }

    if (kDebugMode) {
      print('🔍 Inizio discovery automatica del server selenium...');
    }

    // Priorità basata sulla piattaforma
    List<String> orderedIPs = [];

    if (kIsWeb) {
      // Web: prova prima localhost, poi IP specifici
      orderedIPs = ['localhost:5001', '172.20.10.3:5001', '192.168.1.100:5001', '10.0.2.2:5001'];
    } else if (Platform.isAndroid) {
      // Android: prova prima Render, poi rete locale
      orderedIPs = [
        'aurora-selenium-api2.onrender.com',  // Server Render (cloud)
        '192.168.1.13:5001',   // IP attuale del server (rete locale)
        '192.168.1.100:5001',  // Casa/ufficio principale
        '10.0.2.2:5001',       // Android emulator
        'localhost:5001',      // Localhost fallback
      ];
    } else if (Platform.isIOS) {
      // iOS: prova prima localhost, poi IP esterni
      orderedIPs = ['localhost:5001', '172.20.10.3:5001', '192.168.1.100:5001', '10.0.2.2:5001'];
    } else {
      // Desktop: usa lista standard
      orderedIPs = List.from(_possibleIPs);
    }

    for (final ip in orderedIPs) {
      try {
        // Determina protocollo: HTTPS per Render, HTTP per il resto
        final protocol = ip.contains('onrender.com') ? 'https' : 'http';
        final fullUrl = '$protocol://$ip';

        if (kDebugMode) {
          print('🔍 Testando server: $fullUrl/health');
        }

        final response = await http.get(
          Uri.parse('$fullUrl/health'),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 8));

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          if (data['service'] == 'selenium-api-server') {
            _serverBaseUrl = fullUrl;
            if (kDebugMode) {
              print('✅ Server selenium trovato: $_serverBaseUrl');
            }
            return _serverBaseUrl;
          }
        }
      } catch (e) {
        if (kDebugMode) {
          print('❌ $ip non raggiungibile: $e');
        }
      }
    }

    if (kDebugMode) {
      print('❌ Nessun server selenium trovato sui IP testati');
    }
    return null;
  }

  DateTime _getWeekStart(DateTime date) {
    // Calcola l'inizio della settimana dal SABATO (weekday 6)
    final dayOfWeek = date.weekday;

    // Se è sabato (6), inizia da sabato stesso
    // Se è domenica (7), inizia dal sabato precedente (-1 giorno)
    // Se è lunedì-venerdì (1-5), inizia dal sabato precedente
    int daysToSubtract;
    if (dayOfWeek == DateTime.saturday) {
      daysToSubtract = 0; // Sabato stesso
    } else if (dayOfWeek == DateTime.sunday) {
      daysToSubtract = 1; // Sabato precedente
    } else {
      // Lunedì-Venerdì: vai al sabato precedente
      daysToSubtract = dayOfWeek + 1;
    }

    return DateTime(date.year, date.month, date.day - daysToSubtract);
  }

  void _goToPreviousWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.subtract(const Duration(days: 7));
    });
    // Ricarica i risultati per la nuova settimana
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ResultsService>().loadResults(weekStart: _currentDate);
    });
  }

  void _goToNextWeek() {
    setState(() {
      _currentWeekStart = _currentWeekStart.add(const Duration(days: 7));
    });
    // Ricarica i risultati per la nuova settimana
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ResultsService>().loadResults(weekStart: _currentDate);
    });
  }

  DateTime? _findPreviousMatchDay() {
    final resultsService = context.read<ResultsService>();
    final currentDayStart = DateTime(_currentDate.year, _currentDate.month, _currentDate.day);

    // Prima cerca nella settimana corrente
    for (int i = 1; i <= 7; i++) {
      final checkDate = currentDayStart.subtract(Duration(days: i));
      final hasMatches = resultsService.results.any((result) {
        final matchDay = DateTime(result.matchDate.year, result.matchDate.month, result.matchDate.day);
        return matchDay.isAtSameMomentAs(checkDate);
      });
      if (hasMatches) {
        return checkDate;
      }
    }

    // Se non trova nella settimana corrente, restituisce null
    // La logica di caricamento delle settimane adiacenti è ora gestita nelle funzioni di navigazione
    return null;
  }

  DateTime? _findNextMatchDay() {
    final resultsService = context.read<ResultsService>();
    final currentDayStart = DateTime(_currentDate.year, _currentDate.month, _currentDate.day);

    // Prima cerca nella settimana corrente
    for (int i = 1; i <= 7; i++) {
      final checkDate = currentDayStart.add(Duration(days: i));
      final hasMatches = resultsService.results.any((result) {
        final matchDay = DateTime(result.matchDate.year, result.matchDate.month, result.matchDate.day);
        return matchDay.isAtSameMomentAs(checkDate);
      });
      if (hasMatches) {
        return checkDate;
      }
    }

    // Se non trova nella settimana corrente, restituisce null
    // La logica di caricamento delle settimane adiacenti è ora gestita nelle funzioni di navigazione
    return null;
  }


  Future<void> _goToPreviousDay() async {
    // Esci dalla modalità classifica quando si naviga tra i giorni
    if (_isStandingsMode) {
      _exitStandingsMode();
    }

    final resultsService = context.read<ResultsService>();

    // Cerca il giorno precedente con partite (fino a 14 giorni indietro)
    DateTime? previousMatchDay;

    for (int i = 1; i <= 14; i++) {
      final checkDate = _currentDate.subtract(Duration(days: i));

      if (kDebugMode) {
        debugPrint('🔍 Checking previous day: ${DateFormat('dd/MM/yy').format(checkDate)}');
      }

      // Carica i risultati per quel giorno specifico
      await resultsService.loadResults(weekStart: checkDate);

      // Controlla se ci sono partite agonistiche Aurora in quel giorno
      final hasAuroraMatches = resultsService.results.any((result) {
        final matchDay = DateTime(result.matchDate.year, result.matchDate.month, result.matchDate.day);
        final checkDayStart = DateTime(checkDate.year, checkDate.month, checkDate.day);
        final isCurrentDay = matchDay.isAtSameMomentAs(checkDayStart);

        final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                             result.awayTeam.toLowerCase().contains('aurora');
        final isAgonistic = _isAgonisticCategory(result.category);

        return isCurrentDay && isAuroraMatch && isAgonistic;
      });

      if (hasAuroraMatches) {
        previousMatchDay = checkDate;
        break;
      }
    }

    if (previousMatchDay != null) {
      setState(() {
        _currentDate = previousMatchDay!;
        _currentWeekStart = _getWeekStart(previousMatchDay!);
      });

      if (kDebugMode) {
        debugPrint('✅ Navigated to previous day: ${DateFormat('dd/MM/yy').format(previousMatchDay!)}');
      }

      // Carica le posizioni per le partite Aurora del nuovo giorno
      _loadPositionsForAuroraMatches().catchError((error) {
        if (kDebugMode) {
          debugPrint('❌ Errore caricamento posizioni dopo navigazione: $error');
        }
      });
    } else {
      if (kDebugMode) {
        debugPrint('❌ No previous match day found in the last 14 days');
      }
    }
  }

  Future<void> _goToNextDay() async {
    // Esci dalla modalità classifica quando si naviga tra i giorni
    if (_isStandingsMode) {
      _exitStandingsMode();
    }

    final resultsService = context.read<ResultsService>();

    // Cerca il giorno successivo con partite (fino a 14 giorni avanti)
    DateTime? nextMatchDay;

    for (int i = 1; i <= 14; i++) {
      final checkDate = _currentDate.add(Duration(days: i));

      if (kDebugMode) {
        debugPrint('🔍 Checking next day: ${DateFormat('dd/MM/yy').format(checkDate)}');
      }

      // Carica i risultati per quel giorno specifico
      await resultsService.loadResults(weekStart: checkDate);

      // Controlla se ci sono partite agonistiche Aurora in quel giorno
      final hasAuroraMatches = resultsService.results.any((result) {
        final matchDay = DateTime(result.matchDate.year, result.matchDate.month, result.matchDate.day);
        final checkDayStart = DateTime(checkDate.year, checkDate.month, checkDate.day);
        final isCurrentDay = matchDay.isAtSameMomentAs(checkDayStart);

        final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                             result.awayTeam.toLowerCase().contains('aurora');
        final isAgonistic = _isAgonisticCategory(result.category);

        return isCurrentDay && isAuroraMatch && isAgonistic;
      });

      if (hasAuroraMatches) {
        nextMatchDay = checkDate;
        break;
      }
    }

    if (nextMatchDay != null) {
      setState(() {
        _currentDate = nextMatchDay!;
        _currentWeekStart = _getWeekStart(nextMatchDay!);
      });

      if (kDebugMode) {
        debugPrint('✅ Navigated to next day: ${DateFormat('dd/MM/yy').format(nextMatchDay!)}');
      }

      // Carica le posizioni per le partite Aurora del nuovo giorno
      _loadPositionsForAuroraMatches().catchError((error) {
        if (kDebugMode) {
          debugPrint('❌ Errore caricamento posizioni dopo navigazione: $error');
        }
      });
    } else {
      if (kDebugMode) {
        debugPrint('❌ No next match day found in the next 14 days');
      }
    }
  }

  DateTime? _findFirstMatchDayInLoadedResults() {
    final resultsService = context.read<ResultsService>();
    if (resultsService.results.isEmpty) return null;

    final sortedDates = resultsService.results
        .map((r) => DateTime(r.matchDate.year, r.matchDate.month, r.matchDate.day))
        .toSet()
        .toList()
      ..sort();

    return sortedDates.isNotEmpty ? sortedDates.first : null;
  }

  DateTime? _findLastMatchDayInLoadedResults() {
    final resultsService = context.read<ResultsService>();
    if (resultsService.results.isEmpty) return null;

    final sortedDates = resultsService.results
        .map((r) => DateTime(r.matchDate.year, r.matchDate.month, r.matchDate.day))
        .toSet()
        .toList()
      ..sort();

    return sortedDates.isNotEmpty ? sortedDates.last : null;
  }

  void _showCalendarDialog() {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text(
            'Seleziona Data',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
          content: SizedBox(
            width: 300,
            height: 400,
            child: CalendarDatePicker(
              initialDate: _currentDate,
              firstDate: DateTime(2024, 1, 1),
              lastDate: DateTime(2025, 12, 31),
              onDateChanged: (DateTime selectedDate) {
                Navigator.of(context).pop();
                _navigateToSelectedDate(selectedDate);
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Annulla',
                style: TextStyle(color: Color(0xFF1E3A8A)),
              ),
            ),
          ],
        );
      },
    );
  }

  void _navigateToSelectedDate(DateTime selectedDate) async {
    final newWeekStart = _getWeekStart(selectedDate);
    final resultsService = context.read<ResultsService>();

    // Carica i risultati per il giorno selezionato
    await resultsService.loadResults(weekStart: selectedDate);

    setState(() {
      _currentDate = selectedDate;
      _currentWeekStart = newWeekStart;
    });
  }

  void _enterStandingsMode(MatchResult match) async {
    // Determina la categoria dalla partita e pulisci il nome
    String? category = _cleanCategoryName(match.category);
    if (category == null) return;

    setState(() {
      _isStandingsMode = true;
      _selectedMatch = match;
      _currentStandings = null; // Reset standings
    });

    if (kDebugMode) {
      print('🔄 Caricamento classifica per $category...');
    }

    // Scarica la classifica in tempo reale con timeout
    try {
      final serverUrl = await _discoverServerUrl();
      if (serverUrl == null) {
        setState(() {
          _currentStandings = {}; // Imposta vuoto per fermare il loading
        });
        if (kDebugMode) {
          print('❌ Server selenium non trovato per visualizzazione classifica $category');
        }
        return;
      }

      final response = await http.get(
        Uri.parse('$serverUrl/standings/$category'),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (kDebugMode) {
          print('📡 Risposta API $category ricevuta: ${response.body.length} chars');
          print('📊 success=${data['success']}, standings keys=${data['standings'] != null ? data['standings'].keys.length : 'null'}');
        }
        if (data['success'] == true && data['standings'] != null) {
          setState(() {
            _currentStandings = data['standings'];
          });
          if (kDebugMode) {
            print('✅ Classifica $category caricata: ${data['standings'].length} squadre');
          }
        } else {
          // API ha risposto ma nessuna classifica trovata
          setState(() {
            _currentStandings = {}; // Imposta vuoto per fermare il loading
          });
          if (kDebugMode) {
            print('⚠️ Nessuna classifica trovata per $category - success: ${data['success']}, standings: ${data['standings']}');
          }
        }
      } else {
        // Errore HTTP
        setState(() {
          _currentStandings = {}; // Imposta vuoto per fermare il loading
        });
        if (kDebugMode) {
          print('❌ Errore HTTP ${response.statusCode} per $category');
        }
      }
    } catch (e) {
      // Timeout o errore di rete
      setState(() {
        _currentStandings = {}; // Imposta vuoto per fermare il loading
      });
      if (kDebugMode) {
        print('❌ Errore caricamento classifica $category: $e');
      }
    }
  }

  void _exitStandingsMode() {
    setState(() {
      _isStandingsMode = false;
      _selectedMatch = null;
      _currentStandings = null;
    });
  }

  @override
  Widget build(BuildContext context) {
    // Mostra la data corrente invece del range settimanale
    final currentDateText = DateFormat('EEEE dd/MM/yy', 'it').format(_currentDate);

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'Risultati',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Badge live monitoring
          Consumer<LiveMatchMonitor>(
            builder: (context, monitor, child) {
              return IconButton(
                onPressed: () => _showLiveMonitorDialog(monitor),
                icon: Stack(
                  children: [
                    Icon(
                      monitor.isMonitoring ? Icons.live_tv : Icons.radio_button_unchecked,
                      color: monitor.isMonitoring ? Colors.red : Colors.white,
                    ),
                    if (monitor.hasNewUpdates)
                      Positioned(
                        right: 0,
                        top: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Colors.orange,
                            shape: BoxShape.circle,
                          ),
                          constraints: const BoxConstraints(
                            minWidth: 12,
                            minHeight: 12,
                          ),
                          child: Text(
                            '${monitor.updatesCount}',
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 8,
                              fontWeight: FontWeight.bold,
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: monitor.isMonitoring ? 'Monitoraggio Live Attivo' : 'Avvia Monitoraggio Live',
              );
            },
          ),
          IconButton(
            onPressed: () => _showWebScrapingDialog(),
            icon: const Icon(Icons.refresh, color: Colors.white),
            tooltip: 'Aggiorna Punteggi e Classifica da Tuttocampo',
          ),
        ],
      ),
      body: Column(
        children: [
          // Header selezione settimana
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Colors.grey.withValues(alpha: 0.1),
                  blurRadius: 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Column(
              children: [
                // Data corrente con frecce di navigazione
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    // Freccia sinistra
                    IconButton(
                      onPressed: _goToPreviousDay,
                      icon: const Icon(Icons.chevron_left),
                      color: const Color(0xFF1E3A8A),
                      iconSize: 28,
                    ),

                    // Data corrente cliccabile per calendario
                    GestureDetector(
                      onTap: _showCalendarDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFF1E3A8A), width: 1),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              currentDateText,
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1E3A8A),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Icon(
                              Icons.calendar_today,
                              color: Color(0xFF1E3A8A),
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Freccia destra
                    IconButton(
                      onPressed: _goToNextDay,
                      icon: const Icon(Icons.chevron_right),
                      color: const Color(0xFF1E3A8A),
                      iconSize: 28,
                    ),
                  ],
                ),
              ],
            ),
          ),

          // Contenuto risultati con swipe gesture per giorni
          Expanded(
            child: GestureDetector(
              onHorizontalDragEnd: (DragEndDetails details) {
                // Rileva swipe orizzontale per navigazione giorni
                if (details.primaryVelocity != null) {
                  if (details.primaryVelocity! > 500) {
                    // Swipe da sinistra a destra → giorno precedente
                    if (_isStandingsMode) {
                      _navigateToStandingsPreviousDay();
                    } else {
                      _goToPreviousDay();
                    }
                  } else if (details.primaryVelocity! < -500) {
                    // Swipe da destra a sinistra → giorno successivo
                    if (_isStandingsMode) {
                      _navigateToStandingsNextDay();
                    } else {
                      _goToNextDay();
                    }
                  }
                }
              },
              onVerticalDragEnd: (DragEndDetails details) {
                // Rileva swipe verticale per uscire dalla modalità classifica
                if (_isStandingsMode && details.primaryVelocity != null) {
                  if (details.primaryVelocity!.abs() > 500) {
                    _exitStandingsMode();
                  }
                }
              },
              child: _buildResultsContent(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildResultsContent() {
    // Se siamo in modalità classifica, mostra il contenuto specifico
    if (_isStandingsMode) {
      return _buildStandingsContent();
    }

    return Consumer<ResultsService>(
      builder: (context, resultsService, child) {
        if (resultsService.isLoading) {
          return const Center(
            child: CircularProgressIndicator(
              color: Color(0xFF1E3A8A),
            ),
          );
        }

        if (resultsService.errorMessage != null) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline,
                  color: Colors.red,
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  resultsService.errorMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    fontSize: 16,
                    color: Colors.red,
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton(
                  onPressed: () => resultsService.loadResults(weekStart: _currentDate),
                  child: const Text('Riprova'),
                ),
              ],
            ),
          );
        }

        final filteredResults = _getFilteredResults(resultsService);

        if (filteredResults.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.sports_score,
                  color: Colors.grey[400],
                  size: 64,
                ),
                const SizedBox(height: 16),
                Text(
                  'Nessun risultato disponibile\nper questo giorno',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    color: Colors.grey[600],
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          );
        }

        return RefreshIndicator(
          onRefresh: () => resultsService.loadResults(weekStart: _currentDate),
          color: const Color(0xFF1E3A8A),
          child: ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: _getItemCount(filteredResults),
            itemBuilder: (context, index) {
              return _buildListItem(filteredResults, index);
            },
          ),
        );
      },
    );
  }

  List<MatchResult> _getFilteredResults(ResultsService resultsService) {
    // Filtra per il giorno corrente selezionato
    final startOfDay = DateTime(_currentDate.year, _currentDate.month, _currentDate.day);
    final endOfDay = startOfDay.add(const Duration(days: 1)).subtract(const Duration(milliseconds: 1));

    // Mostra solo le partite del giorno corrente e squadre agonistiche Aurora
    return resultsService.results.where((result) {
      final matchDay = DateTime(result.matchDate.year, result.matchDate.month, result.matchDate.day);
      final isCurrentDay = matchDay.isAtSameMomentAs(startOfDay);

      // Se è una partita Aurora, filtra solo le agonistiche
      final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                           result.awayTeam.toLowerCase().contains('aurora');

      if (isAuroraMatch) {
        return isCurrentDay && _isAgonisticCategory(result.category);
      }

      // Se non è Aurora, mostra tutte le partite del giorno
      return isCurrentDay;
    }).toList();
  }

  int _getItemCount(List<MatchResult> results) {
    if (results.isEmpty) return 0;

    // Ora contiamo solo le partite, senza headers
    return results.length;
  }

  Widget _buildListItem(List<MatchResult> results, int index) {
    // Semplicemente ritorna la card per la partita all'index specificato
    if (index < results.length) {
      return _buildResultCard(results[index], isFirstOfDay: false);
    }
    return const SizedBox.shrink();
  }



  Widget _buildStandingsContent() {
    return Container(
      color: const Color(0xFF1E3A8A),
      child: Column(
        children: [
          // Partita selezionata in alto
          if (_selectedMatch != null) ...[
            Container(
              margin: const EdgeInsets.all(16),
              child: GestureDetector(
                onTap: () => _exitStandingsMode(),
                child: _buildResultCard(_selectedMatch!, isFirstOfDay: false),
              ),
            ),
            const Divider(color: Colors.white54, height: 1),
          ],

          // Classifica
          Expanded(
            child: Container(
              color: Colors.white,
              child: _currentStandings == null
                  ? const Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          CircularProgressIndicator(color: Color(0xFF1E3A8A)),
                          SizedBox(height: 16),
                          Text(
                            'Caricamento classifica...',
                            style: TextStyle(
                              fontSize: 16,
                              color: Color(0xFF1E3A8A),
                            ),
                          ),
                        ],
                      ),
                    )
                  : _buildStandingsTable(),
            ),
          ),

          // Istruzioni per uscire
          Container(
            padding: const EdgeInsets.all(16),
            color: const Color(0xFF1E3A8A),
            child: const Text(
              'Swipe orizzontalmente per tornare ai risultati',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white70,
                fontSize: 14,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStandingsTable() {
    if (_currentStandings == null || _currentStandings!.isEmpty) {
      return const Center(
        child: Text(
          'Nessuna classifica disponibile',
          style: TextStyle(
            fontSize: 16,
            color: Colors.grey,
          ),
        ),
      );
    }

    // Converti la mappa in lista ordinata per posizione
    final List<MapEntry<String, dynamic>> sortedTeams = _currentStandings!.entries.toList()
      ..sort((a, b) => (a.value['position'] ?? 999).compareTo(b.value['position'] ?? 999));

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: sortedTeams.length,
      itemBuilder: (context, index) {
        final team = sortedTeams[index];
        final teamData = team.value;
        final position = teamData['position'] ?? 0;
        final teamName = teamData['team_name'] ?? team.key;
        final points = teamData['points'] ?? 0;
        final played = teamData['played'] ?? 0;
        final wins = teamData['wins'] ?? 0;
        final draws = teamData['draws'] ?? 0;
        final losses = teamData['losses'] ?? 0;
        final goalsFor = teamData['goals_for'] ?? 0;
        final goalsAgainst = teamData['goals_against'] ?? 0;
        final isAuroraTeam = teamName.toLowerCase().contains('aurora');

        // Identifica la squadra avversaria di Aurora dalla partita selezionata
        String? opponentTeam;
        if (_selectedMatch != null) {
          final isAuroraHome = _selectedMatch!.homeTeam.toLowerCase().contains('aurora');
          final isAuroraAway = _selectedMatch!.awayTeam.toLowerCase().contains('aurora');

          if (isAuroraHome) {
            opponentTeam = _selectedMatch!.awayTeam.toLowerCase();
          } else if (isAuroraAway) {
            opponentTeam = _selectedMatch!.homeTeam.toLowerCase();
          }
        }

        final isOpponentTeam = opponentTeam != null &&
                              (teamName.toLowerCase().contains(opponentTeam) ||
                               opponentTeam.contains(teamName.toLowerCase()));

        return Container(
          margin: const EdgeInsets.only(bottom: 1),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          decoration: BoxDecoration(
            color: isAuroraTeam
                ? Colors.blue.shade50
                : isOpponentTeam
                  ? Colors.yellow.shade50
                  : Colors.transparent,
          ),
          child: Row(
            children: [
              // Posizione
              SizedBox(
                width: 20,
                child: Text(
                  '$position',
                  style: TextStyle(
                    color: isAuroraTeam ? Colors.blue.shade700 : Colors.grey.shade700,
                    fontWeight: FontWeight.bold,
                    fontSize: 12,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(width: 8),

              // Nome squadra
              Expanded(
                child: Text(
                  teamName,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),

              // Statistiche
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildStatColumn('PT', '$points', isPoints: true),
                  const SizedBox(width: 8),
                  _buildStatColumn('G', '$played'),
                  const SizedBox(width: 8),
                  _buildStatColumn('V', '$wins'),
                  const SizedBox(width: 8),
                  _buildStatColumn('P', '$draws'),
                  const SizedBox(width: 8),
                  _buildStatColumn('S', '$losses'),
                  const SizedBox(width: 8),
                  _buildStatColumn('GF', '$goalsFor'),
                  const SizedBox(width: 8),
                  _buildStatColumn('GS', '$goalsAgainst'),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildStatColumn(String label, String value, {bool isPoints = false}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 8,
            fontWeight: FontWeight.w500,
            color: Colors.grey,
          ),
        ),
        Text(
          value,
          style: TextStyle(
            fontSize: 10,
            fontWeight: isPoints ? FontWeight.bold : FontWeight.normal,
            color: isPoints ? Colors.black : Colors.grey.shade600,
          ),
        ),
      ],
    );
  }

  // Funzione per calcolare la durata totale della partita per categoria
  int _getMatchDurationMinutes(String? category) {
    if (category == null) return 105; // Default: 90 + 15

    final cat = category.toUpperCase();

    if (cat.contains('PROMOZIONE') || cat.contains('U19') || cat.contains('U21') ||
        cat.contains('U18') || cat.contains('U17')) {
      return 105; // 2x45 + 15 intervallo + 5 recupero = 105 minuti
    } else if (cat.contains('U16')) {
      return 95; // 2x40 + 15 intervallo + 5 recupero = 95 minuti
    } else if (cat.contains('U15') || cat.contains('U14')) {
      return 85; // 2x35 + 15 intervallo + 5 recupero = 85 minuti
    }

    return 105; // Default
  }

  Widget _buildResultCard(MatchResult result, {bool isFirstOfDay = false}) {
    final dateFormat = DateFormat('dd/MM/yy', 'it');
    final timeFormat = DateFormat('HH:mm', 'it');
    final dayFormat = DateFormat('EEEE', 'it');

    // Stile ispirato a tuttocampo.it
    final isAuroraHome = result.homeTeam.toLowerCase().contains('aurora');
    final isAuroraAway = result.awayTeam.toLowerCase().contains('aurora');
    final isAuroraMatch = isAuroraHome || isAuroraAway;

    // Determina lo stato automatico se non è stato impostato
    final currentStatus = result.status == MatchStatus.notStarted ? result.autoStatus : result.status;

    // UI con colori dinamici basati sullo stato
    Color backgroundColor = Colors.white;
    Color borderColor;
    Color resultColor;
    Color statusIndicatorColor;

    switch (currentStatus) {
      case MatchStatus.notStarted:
        borderColor = const Color(0xFFE0E0E0);
        resultColor = const Color(0xFF9E9E9E); // Grigio
        statusIndicatorColor = const Color(0xFF9E9E9E);
        break;
      case MatchStatus.inProgress:
        borderColor = const Color(0xFFE53935); // Bordo rosso per partite in corso
        resultColor = const Color(0xFFE53935); // Punteggio rosso
        statusIndicatorColor = const Color(0xFFE53935);
        backgroundColor = const Color(0xFFFFF5F5); // Sfondo leggermente rosso
        break;
      case MatchStatus.finished:
        borderColor = const Color(0xFFE0E0E0);
        resultColor = const Color(0xFF212121); // Nero per partite finite
        statusIndicatorColor = const Color(0xFF4CAF50); // Verde per finite
        break;
      case MatchStatus.postponed:
        borderColor = const Color(0xFFFF9800);
        resultColor = const Color(0xFFFF9800); // Arancione
        statusIndicatorColor = const Color(0xFFFF9800);
        backgroundColor = const Color(0xFFFFF8E1); // Sfondo leggermente arancione
        break;
    }

    // Calcola orario fine basato sulla categoria
    final matchDuration = _getMatchDurationMinutes(result.category);
    final matchEndTime = result.matchDate.add(Duration(minutes: matchDuration));
    final endTimeFormat = DateFormat('HH:mm', 'it');

    Widget cardContent = Column(
      children: [

        // Card principale ridotta
        Container(
          margin: EdgeInsets.only(bottom: 4, top: isFirstOfDay ? 0 : 4),
          decoration: BoxDecoration(
            color: backgroundColor,
            border: Border.all(color: borderColor, width: 1),
            borderRadius: BorderRadius.circular(4),
            boxShadow: [
              BoxShadow(
                color: Colors.grey.withValues(alpha: 0.1),
                spreadRadius: 1,
                blurRadius: 2,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Padding(
            padding: const EdgeInsets.all(8), // Ridotto da 12 a 8
            child: Column(
              children: [
                // Prima riga: orari dentro la card
                Row(
                  children: [
                    // Orario inizio (sinistra)
                    Text(
                      timeFormat.format(result.matchDate),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),

                    // Centro: TERMINATA/IN CORSO con animazione
                    Expanded(
                      child: Center(
                        child: currentStatus == MatchStatus.inProgress
                          ? TweenAnimationBuilder<double>(
                              duration: const Duration(milliseconds: 1000),
                              tween: Tween(begin: 0.3, end: 1.0),
                              builder: (context, value, child) {
                                return Opacity(
                                  opacity: value,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.red.withValues(alpha: 0.1),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(color: Colors.red, width: 1),
                                    ),
                                    child: const Text(
                                      'IN CORSO',
                                      style: TextStyle(
                                        fontSize: 8,
                                        fontWeight: FontWeight.bold,
                                        color: Colors.red,
                                      ),
                                    ),
                                  ),
                                );
                              },
                              onEnd: () {
                                // Ricrea l'animazione per l'effetto lampeggiante continuo
                                if (mounted && currentStatus == MatchStatus.inProgress) {
                                  setState(() {});
                                }
                              },
                            )
                          : currentStatus == MatchStatus.finished
                            ? Container(
                                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.green.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Colors.green, width: 1),
                                ),
                                child: const Text(
                                  'TERMINATA',
                                  style: TextStyle(
                                    fontSize: 8,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.green,
                                  ),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                    ),

                    // Orario fine (destra)
                    Text(
                      endTimeFormat.format(matchEndTime),
                      style: const TextStyle(
                        fontSize: 9,
                        fontWeight: FontWeight.w500,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 6),

                // Loghi e punteggio usando Stack per centraggio perfetto
                SizedBox(
                  height: 32, // Ridotto da 40 a 32
                  child: Stack(
                    children: [
                      // Logo casa a sinistra
                      Positioned(
                        left: 0,
                        top: 0,
                        child: FastTeamLogo(
                          teamName: result.homeTeam,
                          size: 28, // Ridotto da 32 a 28
                          fallbackColor: resultColor.withValues(alpha: 0.7),
                        ),
                      ),
                      // Punteggio al centro assoluto
                      Center(
                        child: GestureDetector(
                          onTap: result.id != null ? () => _showManualScoreDialog(result) : null,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), // Ridotto padding
                            child: Text(
                              result.score,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.bold,
                                color: resultColor,
                              ),
                            ),
                          ),
                        ),
                      ),
                      // Logo ospite a destra
                      Positioned(
                        right: 0,
                        top: 0,
                        child: FastTeamLogo(
                          teamName: result.awayTeam,
                          size: 28, // Ridotto da 32 a 28
                          fallbackColor: resultColor.withValues(alpha: 0.7),
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 6), // Ridotto da 8 a 6

                // Nomi delle squadre con posizioni
                Row(
                  children: [
                    // Squadra di casa
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isAuroraHome && result.category != null ? result.category! : result.homeTeam,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: isAuroraHome ? FontWeight.bold : FontWeight.w600,
                              color: isAuroraHome ? const Color(0xFF1976D2) : const Color(0xFF333333),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            // Mostra posizione reale per squadre Aurora agonistiche
                            isAuroraHome
                              ? (result.homePosition != null
                                  ? (result.homePosition == 99 ? 'N/A pos.' : '${result.homePosition}° pos.')
                                  : 'Caricamento pos...')
                              : (result.homePosition != null
                                  ? '${result.homePosition}° pos.'
                                  : 'N/A pos.'),
                            style: const TextStyle(
                              fontSize: 6,
                              color: Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Squadra ospite
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            isAuroraAway && result.category != null ? result.category! : result.awayTeam,
                            textAlign: TextAlign.end,
                            style: TextStyle(
                              fontSize: 8,
                              fontWeight: isAuroraAway ? FontWeight.bold : FontWeight.w600,
                              color: isAuroraAway ? const Color(0xFF1976D2) : const Color(0xFF333333),
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          const SizedBox(height: 1),
                          Text(
                            // Mostra posizione reale per squadre Aurora agonistiche
                            isAuroraAway
                              ? (result.awayPosition != null
                                  ? (result.awayPosition == 99 ? 'N/A pos.' : '${result.awayPosition}° pos.')
                                  : 'Caricamento pos...')
                              : (result.awayPosition != null
                                  ? '${result.awayPosition}° pos.'
                                  : 'N/A pos.'),
                            textAlign: TextAlign.end,
                            style: const TextStyle(
                              fontSize: 6,
                              color: Color(0xFF666666),
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ],
    );

    // Se è una partita Aurora con categoria, rendila cliccabile per vedere la classifica
    if (isAuroraMatch && result.category != null && !_isStandingsMode) {
      return GestureDetector(
        onTap: () => _enterStandingsMode(result),
        child: cardContent,
      );
    }

    return cardContent;
  }

  void _showWebScrapingDialog() {
    // Determina il testo in base alla data corrente
    final currentDateText = DateFormat('EEEE dd/MM', 'it').format(_currentDate);
    String titleText = 'Aggiorna Risultati $currentDateText';
    String bodyText = 'Aggiorna punteggi e posizioni classifica delle partite di ${currentDateText.toLowerCase()}';
    String dayInfo = '\n🏆 Partite del ${currentDateText.toLowerCase()}';

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Text(
            titleText,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: Color(0xFF1E3A8A),
            ),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '$bodyText da tuttocampo.it.$dayInfo',
                style: const TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 12),
              const Text(
                '✅ Vantaggi del sistema ottimizzato:',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: Color(0xFF1976D2)),
              ),
              const SizedBox(height: 6),
              const Text('• Scarica punteggi E posizioni classifica', style: TextStyle(fontSize: 12, color: Colors.green)),
              const Text('• Scraping solo delle categorie necessarie', style: TextStyle(fontSize: 12, color: Colors.green)),
              const Text('• Lettura dalla colonna PT di tuttocampo.it', style: TextStyle(fontSize: 12, color: Colors.green)),
              const Text('• Gestione automatica errori HTTP', style: TextStyle(fontSize: 12, color: Colors.green)),
              const SizedBox(height: 12),
              const Text(
                'ℹ️ Solo le partite programmate nel database verranno aggiornate.',
                style: TextStyle(fontSize: 12, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              const Text(
                'Procedere con l\'aggiornamento?',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text(
                'Annulla',
                style: TextStyle(color: Colors.grey),
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _performWebScraping();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1E3A8A),
                foregroundColor: Colors.white,
              ),
              child: const Text('Aggiorna'),
            ),
          ],
        );
      },
    );
  }

  void _performWebScraping() async {
    if (!mounted) return;
    final resultsService = context.read<ResultsService>();

    // Determina il testo in base alla data corrente
    final currentDateText = DateFormat('EEEE', 'it').format(_currentDate);
    String dayText = 'risultati ${currentDateText.toLowerCase()}';

    // Mostra snackbar di caricamento
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text('Aggiornamento $dayText e classifiche...'),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF1E3A8A),
        duration: const Duration(seconds: 20),
      ),
    );

    try {
      // Aggiorna i risultati per la settimana corrente
      await resultsService.loadResults(weekStart: _currentDate);

      // Nascondi il snackbar precedente
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Conta le partite del giorno specifico
      final filteredResults = _getFilteredResults(resultsService);
      final updatedCount = filteredResults.where((r) => r.homeScore + r.awayScore > 0).length;
      final totalMatches = filteredResults.length;

      // Mostra messaggio di successo o informativo
      String message;
      Color backgroundColor;

      if (updatedCount > 0) {
        message = 'Aggiornamento completato! $updatedCount/$totalMatches risultati e classifiche aggiornati per $dayText.';
        backgroundColor = Colors.green;
      } else if (totalMatches > 0) {
        message = '⚠️ Tuttocampo.it temporaneamente non accessibile. Risultati inseribili manualmente con il pulsante ➕ in alto a destra.';
        backgroundColor = Colors.orange;
      } else {
        message = 'Nessuna partita programmata per $dayText.';
        backgroundColor = Colors.blue;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: backgroundColor,
          duration: const Duration(seconds: 4),
        ),
      );
    } catch (error) {
      // Nascondi il snackbar precedente
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      // Mostra messaggio di errore
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Errore durante l\'aggiornamento: $error'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  Future<void> _showManualScoreDialog(MatchResult match) async {
    final result = await showDialog<Map<String, int>>(
      context: context,
      builder: (context) => ManualScoreDialog(match: match),
    );

    if (result != null) {
      final homeScore = result['homeScore']!;
      final awayScore = result['awayScore']!;

      // Verifica che la partita abbia un ID valido
      if (match.id == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Errore: ID partita non valido'),
              backgroundColor: Colors.red,
              duration: Duration(seconds: 3),
            ),
          );
        }
        return;
      }

      try {
        final resultsService = context.read<ResultsService>();

        // Aggiorna il risultato nel servizio
        await resultsService.updateMatchScore(
          match.id!,
          homeScore,
          awayScore,
        );

        // Mostra messaggio di successo
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Risultato aggiornato: ${match.homeTeam} $homeScore-$awayScore ${match.awayTeam}',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(seconds: 3),
            ),
          );
        }
      } catch (error) {
        // Mostra messaggio di errore
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Errore durante l\'aggiornamento: $error'),
              backgroundColor: Colors.red,
              duration: const Duration(seconds: 4),
            ),
          );
        }
      }
    }
  }


  String _getStatusLabel(MatchStatus status) {
    switch (status) {
      case MatchStatus.notStarted:
        return 'NON INIZIATA';
      case MatchStatus.inProgress:
        return 'IN CORSO';
      case MatchStatus.finished:
        return 'FINITA';
      case MatchStatus.postponed:
        return 'RINVIATA';
    }
  }

  void _showLiveMonitorDialog(LiveMatchMonitor monitor) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  Icon(
                    monitor.isMonitoring ? Icons.live_tv : Icons.radio_button_unchecked,
                    color: monitor.isMonitoring ? Colors.red : Colors.grey,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  const Text(
                    'Monitoraggio Live',
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF1E3A8A),
                    ),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    monitor.isMonitoring
                        ? '🔴 Monitoraggio attivo - Controllo ogni minuto'
                        : '⚪ Monitoraggio non attivo',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: monitor.isMonitoring ? Colors.green : Colors.grey,
                    ),
                  ),
                  const SizedBox(height: 16),
                  const Text(
                    'Il monitoraggio live:',
                    style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                  ),
                  const SizedBox(height: 8),
                  const Text('• Controlla automaticamente i punteggi ogni minuto', style: TextStyle(fontSize: 12)),
                  const Text('• Cambia i colori quando le partite iniziano (ROSSO)', style: TextStyle(fontSize: 12)),
                  const Text('• Emette un beep quando ci sono cambiamenti', style: TextStyle(fontSize: 12)),
                  const Text('• Mostra un badge con il numero di aggiornamenti', style: TextStyle(fontSize: 12)),

                  if (monitor.isMonitoring) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Aggiornamenti: ${monitor.updatesCount}',
                            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
                          ),
                          if (monitor.lastUpdate != null)
                            Text(
                              'Ultimo controllo: ${DateFormat('HH:mm:ss').format(monitor.lastUpdate!)}',
                              style: const TextStyle(fontSize: 11, color: Colors.grey),
                            ),
                        ],
                      ),
                    ),
                  ],

                  if (monitor.updateMessages.isNotEmpty) ...[
                    const SizedBox(height: 16),
                    const Text(
                      'Ultimi aggiornamenti:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    const SizedBox(height: 8),
                    Container(
                      height: 100,
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: Colors.blue.shade200),
                      ),
                      child: ListView.builder(
                        itemCount: monitor.updateMessages.length,
                        itemBuilder: (context, index) {
                          final message = monitor.updateMessages[monitor.updateMessages.length - 1 - index];
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 2),
                            child: Text(
                              message,
                              style: const TextStyle(fontSize: 11),
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                ],
              ),
              actions: [
                if (monitor.hasNewUpdates)
                  TextButton(
                    onPressed: () {
                      monitor.markNotificationsAsRead();
                      setState(() {});
                    },
                    child: const Text('Segna come letto'),
                  ),
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Chiudi'),
                ),
                ElevatedButton(
                  onPressed: () {
                    if (monitor.isMonitoring) {
                      monitor.stopMonitoring();
                    } else {
                      monitor.startMonitoring();
                    }
                    setState(() {});
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: monitor.isMonitoring ? Colors.red : const Color(0xFF1E3A8A),
                    foregroundColor: Colors.white,
                  ),
                  child: Text(monitor.isMonitoring ? 'Ferma' : 'Avvia'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// Test specifico per U21 scraping (solo debug mode)

  /// Naviga al giorno precedente in modalità classifica
  void _navigateToStandingsPreviousDay() async {
    // Prima naviga al giorno precedente con partite Aurora
    await _goToPreviousDay();

    // Se siamo ancora in modalità classifica e abbiamo una partita selezionata
    if (_isStandingsMode && _selectedMatch != null) {
      // Cerca una partita Aurora agonistica nel nuovo giorno
      final resultsService = context.read<ResultsService>();
      final filteredResults = _getFilteredResults(resultsService);

      final auroraMatches = filteredResults.where((result) {
        final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                             result.awayTeam.toLowerCase().contains('aurora');
        final isAgonistic = _isAgonisticCategory(result.category);
        return isAuroraMatch && isAgonistic;
      }).toList();

      final auroraMatch = auroraMatches.isNotEmpty ? auroraMatches.first : null;

      if (auroraMatch != null) {
        // Aggiorna la partita selezionata e ricarica la classifica
        _enterStandingsMode(auroraMatch);
      } else {
        // Se non ci sono partite Aurora, esci dalla modalità classifica
        _exitStandingsMode();
      }
    }
  }

  /// Naviga al giorno successivo in modalità classifica
  void _navigateToStandingsNextDay() async {
    // Prima naviga al giorno successivo con partite Aurora
    await _goToNextDay();

    // Se siamo ancora in modalità classifica e abbiamo una partita selezionata
    if (_isStandingsMode && _selectedMatch != null) {
      // Cerca una partita Aurora agonistica nel nuovo giorno
      final resultsService = context.read<ResultsService>();
      final filteredResults = _getFilteredResults(resultsService);

      final auroraMatches = filteredResults.where((result) {
        final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                             result.awayTeam.toLowerCase().contains('aurora');
        final isAgonistic = _isAgonisticCategory(result.category);
        return isAuroraMatch && isAgonistic;
      }).toList();

      final auroraMatch = auroraMatches.isNotEmpty ? auroraMatches.first : null;

      if (auroraMatch != null) {
        // Aggiorna la partita selezionata e ricarica la classifica
        _enterStandingsMode(auroraMatch);
      } else {
        // Se non ci sono partite Aurora, esci dalla modalità classifica
        _exitStandingsMode();
      }
    }
  }
}