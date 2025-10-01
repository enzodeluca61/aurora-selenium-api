import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/match_model.dart';

class MatchService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Match> _matches = [];
  bool _isLoading = false;
  String? _errorMessage;
  // Static variable to store last match details
  static Map<String, dynamic>? _lastMatchDetails;

  // Weekly matches cache
  final Map<String, List<Match>> _weeklyCache = {};
  final Map<String, DateTime> _cacheTimestamps = {};
  static const Duration _cacheExpiry = Duration(minutes: 15);

  // Static getter for last match details
  static Map<String, dynamic>? get lastMatchDetails => _lastMatchDetails;

  // Static setter for last match details
  static void setLastMatchDetails(Map<String, dynamic> details) {
    _lastMatchDetails = details;
  }

  MatchService() {
    // Ascolta i cambiamenti di autenticazione e ricarica le partite
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null) {
        // Nuovo utente loggato, ricarica le partite
        loadMatches();
      } else {
        // Utente disconnesso, svuota le partite
        _matches = [];
        notifyListeners();
      }
    });
  }

  List<Match> get matches => _matches;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadMatches() async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== LOADING MATCHES ===');
        debugPrint('Current user: ${_supabase.auth.currentUser?.email}');
      }

      final response = await _supabase
          .from('matches')
          .select('*, giornata')
          .order('date', ascending: true);

      _matches = (response as List)
          .map((json) {
            try {
              if (kDebugMode && json['match_type'] == 'campionato') {
                debugPrint('Parsing campionato match - giornata field: ${json['giornata']}');
              }
              return Match.fromJson(json);
            } catch (e) {
              if (kDebugMode) {
                debugPrint('Error parsing match JSON: $e');
                debugPrint('JSON data: $json');
              }
              rethrow;
            }
          })
          .toList();

      if (kDebugMode) {
        debugPrint('Loaded ${_matches.length} matches');
        for (var match in _matches.take(3)) { // Mostra solo le prime 3 per debug
          debugPrint('Match: ${match.opponent} - ${match.matchType} - Giornata: ${match.giornata} - UserId: ${match.userId}');
        }
        // Debug specifico per U21
        final u21Matches = _matches.where((m) => m.auroraTeam == 'U21').toList();
        debugPrint('=== U21 MATCHES DEBUG ===');
        debugPrint('Found ${u21Matches.length} U21 matches');
        for (var match in u21Matches) {
          debugPrint('U21: ${match.opponent} - Date: ${match.date} - Type: ${match.matchType}');
        }
        debugPrint('========================');
      }

      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error loading matches: $error');
      }
      // Se la tabella non esiste, inizializziamo con lista vuota
      if (error.toString().contains('table') || error.toString().contains('relation')) {
        _matches = [];
        notifyListeners();
      } else {
        _setError('Errore nel caricamento delle partite: ${error.toString()}');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addMatch(Match match) async {
    try {
      _setLoading(true);
      _clearError();

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato');
      }

      // Salviamo con userId per policy di sicurezza, ma tutti possono vedere tutte le partite
      final matchData = match.copyWith(userId: user.id);
      
      try {
        final response = await _supabase
            .from('matches')
            .insert(matchData.toJson())
            .select()
            .single();

        final newMatch = Match.fromJson(response);
        _matches.add(newMatch);
      } catch (supabaseError) {
        // Verifica se è un errore di tabella mancante
        if (supabaseError.toString().contains('relation "public.matches" does not exist') ||
            supabaseError.toString().contains('table') ||
            supabaseError.toString().contains('relation')) {
          _setError('Errore: Tabella del database non configurata. Contatta l\'amministratore.');
        }
        // Verifica se è un errore di policy/permissions
        else if (supabaseError.toString().contains('policy') || 
                 supabaseError.toString().contains('permission') ||
                 supabaseError.toString().contains('RLS')) {
          _setError('Errore: Permessi del database. Contatta l\'amministratore.');
        }
        
        // Fallback: salva solo in memoria locale
        final newMatch = match.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        _matches.add(newMatch);
      }

      _matches.sort((a, b) => a.date.compareTo(b.date));
      _clearWeeklyCache(); // Clear cache when new match is added
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta della partita: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateMatch(Match match) async {
    try {
      _setLoading(true);
      _clearError();

      // Debug: stampa il JSON che stiamo inviando
      if (kDebugMode) {
        debugPrint('=== UPDATING MATCH ===');
        debugPrint('Match ID: ${match.id}');
        debugPrint('Match userId: ${match.userId}');
        debugPrint('Current user ID: ${_supabase.auth.currentUser?.id}');
        debugPrint('Match JSON: ${match.toJson()}');
        debugPrint('=====================');
      }

      final response = await _supabase
          .from('matches')
          .update(match.toJson())
          .eq('id', match.id!)
          .select()
          .single();

      if (kDebugMode) {
        debugPrint('=== UPDATE RESPONSE ===');
        debugPrint('Response: $response');
        debugPrint('=====================');
      }

      final updatedMatch = Match.fromJson(response);
      final index = _matches.indexWhere((m) => m.id == match.id);
      if (index != -1) {
        _matches[index] = updatedMatch;
        _matches.sort((a, b) => a.date.compareTo(b.date));
        _clearWeeklyCache(); // Clear cache when match is updated
        notifyListeners();
      }

      return true;
    } catch (error) {
      _setError('Errore nell\'aggiornamento della partita: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteMatch(String matchId) async {
    try {
      _setLoading(true);
      _clearError();

      await _supabase
          .from('matches')
          .delete()
          .eq('id', matchId);

      _matches.removeWhere((match) => match.id == matchId);
      _clearWeeklyCache(); // Clear cache when match is deleted
      notifyListeners();

      return true;
    } catch (error) {
      _setError('Errore nella cancellazione della partita: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  List<Match> getMatchesForDate(DateTime date) {
    return _matches.where((match) {
      return match.date.year == date.year &&
             match.date.month == date.month &&
             match.date.day == date.day;
    }).toList();
  }

  // Optimized weekly matches loading with caching
  Future<List<Match>> loadWeeklyMatches(DateTime weekStart) async {
    final weekEnd = weekStart.add(const Duration(days: 6));
    final cacheKey = '${weekStart.year}-${weekStart.month}-${weekStart.day}';

    // Check cache first
    if (_isValidCache(cacheKey)) {
      if (kDebugMode) {
        debugPrint('Using cached weekly matches for $cacheKey');
      }
      return _weeklyCache[cacheKey]!;
    }

    try {
      if (kDebugMode) {
        debugPrint('Loading weekly matches from database: $weekStart to $weekEnd');
      }

      final response = await _supabase
          .from('matches')
          .select()
          .gte('date', weekStart.toIso8601String().split('T')[0])
          .lte('date', weekEnd.toIso8601String().split('T')[0])
          .order('date', ascending: true)
          .order('time', ascending: true);

      final weeklyMatches = (response as List)
          .map((json) => Match.fromJson(json))
          .toList();

      // Cache the results
      _weeklyCache[cacheKey] = weeklyMatches;
      _cacheTimestamps[cacheKey] = DateTime.now();

      if (kDebugMode) {
        debugPrint('Loaded ${weeklyMatches.length} matches for week $cacheKey');
      }

      return weeklyMatches;
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error loading weekly matches: $error');
      }
      // Fallback to filtering existing matches
      return _getWeeklyMatchesFromCache(weekStart, weekEnd);
    }
  }

  // Check if cache is valid and not expired
  bool _isValidCache(String cacheKey) {
    if (!_weeklyCache.containsKey(cacheKey) || !_cacheTimestamps.containsKey(cacheKey)) {
      return false;
    }

    final cacheTime = _cacheTimestamps[cacheKey]!;
    final isExpired = DateTime.now().difference(cacheTime) > _cacheExpiry;

    if (isExpired) {
      _weeklyCache.remove(cacheKey);
      _cacheTimestamps.remove(cacheKey);
      return false;
    }

    return true;
  }

  // Fallback method to filter from existing matches
  List<Match> _getWeeklyMatchesFromCache(DateTime weekStart, DateTime weekEnd) {
    return _matches.where((match) {
      return match.date.isAfter(weekStart.subtract(const Duration(days: 1))) &&
             match.date.isBefore(weekEnd.add(const Duration(days: 1)));
    }).toList()
      ..sort((a, b) {
        final dateCompare = a.date.compareTo(b.date);
        if (dateCompare != 0) return dateCompare;
        return a.time.compareTo(b.time);
      });
  }

  // Clear cache when matches are modified
  void _clearWeeklyCache() {
    _weeklyCache.clear();
    _cacheTimestamps.clear();
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

  // Metodo per testare la connessione Supabase
  Future<bool> testSupabaseConnection() async {
    try {
      // Test 1: Verifica utente autenticato
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return false;
      }
      
      // Test 2: Prova una query semplice sulla tabella
      try {
        await _supabase
            .from('matches')
            .select('count(*)')
            .count(CountOption.exact);
        return true;
      } catch (e) {
        // Prova a creare una entry test
        try {
          await _supabase
              .from('matches')
              .insert({
                'opponent': 'TEST',
                'date': DateTime.now().toIso8601String(),
                'time': '15:00',
                'location': 'Test Location',
                'is_home': true,
                'user_id': user.id,
              })
              .select()
              .single();
          
          // Pulisci il record test
          await _supabase
              .from('matches')
              .delete()
              .eq('opponent', 'TEST')
              .eq('user_id', user.id);
          
          return true;
        } catch (insertError) {
          return false;
        }
      }
    } catch (e) {
      return false;
    }
  }

  // Metodo per aggiornare una partita solo localmente (per fallback)
  void updateMatchLocally(Match updatedMatch) {
    final index = _matches.indexWhere((match) => match.id == updatedMatch.id);
    if (index != -1) {
      _matches[index] = updatedMatch;
      if (kDebugMode) {
        print('MatchService: Aggiornata partita localmente: ${updatedMatch.opponent}, includeInPlanning: ${updatedMatch.includeInPlanning}');
        print('MatchService: Notificando listener...');
      }
      notifyListeners(); // Notifica tutti i listener che i dati sono cambiati
    } else if (kDebugMode) {
      print('MatchService: ERRORE - Partita non trovata per aggiornamento locale: ${updatedMatch.id}');
    }
  }
}