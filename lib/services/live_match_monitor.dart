import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/result_model.dart';
import 'results_service.dart';

class LiveMatchMonitor extends ChangeNotifier {
  static final LiveMatchMonitor _instance = LiveMatchMonitor._internal();
  factory LiveMatchMonitor() => _instance;
  LiveMatchMonitor._internal();

  Timer? _monitoringTimer;
  final ResultsService _resultsService = ResultsService();
  List<MatchResult> _previousResults = [];
  bool _isMonitoring = false;
  int _updatesCount = 0;
  DateTime? _lastUpdate;

  // Notificazioni
  bool _hasNewUpdates = false;
  List<String> _updateMessages = [];

  // Getters
  bool get isMonitoring => _isMonitoring;
  bool get hasNewUpdates => _hasNewUpdates;
  List<String> get updateMessages => List.unmodifiable(_updateMessages);
  int get updatesCount => _updatesCount;
  DateTime? get lastUpdate => _lastUpdate;

  /// Inizia il monitoraggio automatico delle partite live
  void startMonitoring() {
    if (_isMonitoring) return;

    if (kDebugMode) {
      debugPrint('🔴 Avvio monitoraggio live partite');
    }

    _isMonitoring = true;
    _previousResults = List.from(_resultsService.results);

    // Controllo iniziale
    _checkForUpdates();

    // Timer che controlla ogni minuto
    _monitoringTimer = Timer.periodic(const Duration(minutes: 1), (timer) {
      _checkForUpdates();
    });

    notifyListeners();
  }

  /// Ferma il monitoraggio automatico
  void stopMonitoring() {
    if (!_isMonitoring) return;

    if (kDebugMode) {
      debugPrint('⏹️ Arresto monitoraggio live partite');
    }

    _monitoringTimer?.cancel();
    _monitoringTimer = null;
    _isMonitoring = false;

    notifyListeners();
  }

  /// Controlla se ci sono aggiornamenti nelle partite
  Future<void> _checkForUpdates() async {
    try {
      if (kDebugMode) {
        debugPrint('🔍 Controllo aggiornamenti partite live...');
      }

      // Aggiorna i risultati dal web
      await _resultsService.fetchResultsFromWeb();

      final currentResults = _resultsService.results;
      final updates = _detectChanges(_previousResults, currentResults);

      if (updates.isNotEmpty) {
        _processUpdates(updates);
        _previousResults = List.from(currentResults);
        _lastUpdate = DateTime.now();
        _updatesCount++;

        if (kDebugMode) {
          debugPrint('📢 Trovati ${updates.length} aggiornamenti!');
          for (final update in updates) {
            debugPrint('  - $update');
          }
        }
      }

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Errore nel controllo aggiornamenti: $e');
      }
    }
  }

  /// Rileva cambiamenti tra i risultati precedenti e quelli attuali
  List<String> _detectChanges(List<MatchResult> previous, List<MatchResult> current) {
    final List<String> changes = [];

    // Crea mappa per accesso rapido
    final Map<String, MatchResult> previousMap = {
      for (final result in previous)
        '${result.homeTeam}_${result.awayTeam}_${result.matchDate.day}': result
    };

    for (final currentResult in current) {
      final key = '${currentResult.homeTeam}_${currentResult.awayTeam}_${currentResult.matchDate.day}';
      final previousResult = previousMap[key];

      if (previousResult != null) {
        // Controlla cambiamenti di punteggio
        if (previousResult.homeScore != currentResult.homeScore ||
            previousResult.awayScore != currentResult.awayScore) {
          changes.add(
            '⚽ ${currentResult.homeTeam} ${currentResult.homeScore}-${currentResult.awayScore} ${currentResult.awayTeam}'
          );
        }

        // Controlla cambiamenti di stato
        final previousStatus = previousResult.status == MatchStatus.notStarted
            ? previousResult.autoStatus
            : previousResult.status;
        final currentStatus = currentResult.status == MatchStatus.notStarted
            ? currentResult.autoStatus
            : currentResult.status;

        if (previousStatus != currentStatus) {
          String statusMessage = '';
          switch (currentStatus) {
            case MatchStatus.inProgress:
              statusMessage = '🔴 ${currentResult.homeTeam} vs ${currentResult.awayTeam} - INIZIATA!';
              break;
            case MatchStatus.finished:
              statusMessage = '🏁 ${currentResult.homeTeam} vs ${currentResult.awayTeam} - FINITA!';
              break;
            case MatchStatus.postponed:
              statusMessage = '⏸️ ${currentResult.homeTeam} vs ${currentResult.awayTeam} - RINVIATA';
              break;
            default:
              break;
          }
          if (statusMessage.isNotEmpty) {
            changes.add(statusMessage);
          }
        }
      }
    }

    return changes;
  }

  /// Processa gli aggiornamenti trovati
  void _processUpdates(List<String> updates) {
    _hasNewUpdates = true;
    _updateMessages.addAll(updates);

    // Mantieni solo gli ultimi 10 messaggi
    if (_updateMessages.length > 10) {
      _updateMessages = _updateMessages.sublist(_updateMessages.length - 10);
    }

    // Emetti suono di notifica
    _playNotificationSound();

    notifyListeners();
  }

  /// Emette un suono di notifica
  void _playNotificationSound() {
    try {
      // Usa il feedback haptico per dispositivi mobili
      HapticFeedback.lightImpact();

      // Su iOS/Android puoi usare anche:
      // SystemSound.play(SystemSoundType.notification);

      if (kDebugMode) {
        debugPrint('🔔 Suono di notifica emesso');
      }
    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Errore nel riprodurre suono: $e');
      }
    }
  }

  /// Marca le notifiche come lette
  void markNotificationsAsRead() {
    _hasNewUpdates = false;
    _updateMessages.clear();
    notifyListeners();
  }

  /// Avvia automaticamente il monitoraggio durante i weekend
  void startWeekendMonitoring() {
    final now = DateTime.now();
    final isWeekend = now.weekday == DateTime.saturday || now.weekday == DateTime.sunday;

    // Controlla se è un weekend e se siamo nell'orario delle partite (8:00 - 20:00)
    if (isWeekend && now.hour >= 8 && now.hour <= 20) {
      if (!_isMonitoring) {
        if (kDebugMode) {
          debugPrint('🏈 Avvio automatico monitoraggio weekend');
        }
        startMonitoring();
      }
    } else {
      if (_isMonitoring) {
        if (kDebugMode) {
          debugPrint('🏁 Arresto automatico monitoraggio (fine weekend)');
        }
        stopMonitoring();
      }
    }
  }

  /// Controlla se ci sono partite di Aurora in corso o che inizieranno presto
  bool hasUpcomingOrLiveMatches() {
    final now = DateTime.now();

    return _resultsService.results.any((result) {
      // Controlla se è una partita di Aurora
      final isAuroraMatch = result.homeTeam.toLowerCase().contains('aurora') ||
                           result.awayTeam.toLowerCase().contains('aurora');

      if (!isAuroraMatch) return false;

      // Controlla se è in corso o inizia nelle prossime 2 ore
      final matchStart = result.matchDate;
      final timeDifference = matchStart.difference(now);

      final currentStatus = result.status == MatchStatus.notStarted
          ? result.autoStatus
          : result.status;

      return currentStatus == MatchStatus.inProgress ||
             (currentStatus == MatchStatus.notStarted &&
              timeDifference.inHours <= 2 &&
              timeDifference.inMinutes >= -90); // Fino a 90 minuti dopo l'inizio
    });
  }

  @override
  void dispose() {
    stopMonitoring();
    super.dispose();
  }
}