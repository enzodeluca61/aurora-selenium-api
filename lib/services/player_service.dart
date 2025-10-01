import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_model.dart';
import '../utils/supabase_player_test.dart';

class PlayerService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Player> _players = [];
  List<Player> _staff = [];
  bool _isLoading = false;
  String? _errorMessage;

  // Ordinamento personalizzato per giocatori: prima per numero maglia, poi per nome
  int _comparePlayersByJerseyNumber(Player a, Player b) {
    if (kDebugMode) {
      debugPrint('Comparing: ${a.name}(${a.jerseyNumber}) vs ${b.name}(${b.jerseyNumber})');
    }
    
    // Se entrambi hanno numero maglia, ordina per numero
    if (a.jerseyNumber != null && b.jerseyNumber != null) {
      final result = a.jerseyNumber!.compareTo(b.jerseyNumber!);
      if (kDebugMode) {
        debugPrint('Both have numbers: ${a.jerseyNumber} vs ${b.jerseyNumber} = $result');
      }
      return result;
    }
    // Se solo a ha numero, a viene prima
    if (a.jerseyNumber != null && b.jerseyNumber == null) {
      if (kDebugMode) {
        debugPrint('Only A has number: ${a.name} comes first');
      }
      return -1;
    }
    // Se solo b ha numero, b viene prima  
    if (a.jerseyNumber == null && b.jerseyNumber != null) {
      if (kDebugMode) {
        debugPrint('Only B has number: ${b.name} comes first');
      }
      return 1;
    }
    // Se nessuno ha numero, ordina per nome
    final result = a.name.compareTo(b.name);
    if (kDebugMode) {
      debugPrint('Neither has number, sorting by name: ${a.name} vs ${b.name} = $result');
    }
    return result;
  }

  List<Player> get players => _players;
  List<Player> get staff => _staff;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadPlayers() async {
    try {
      debugPrint('=== LOADING PLAYERS FROM SUPABASE ===');
      _setLoading(true);
      _clearError();

      final response = await _supabase
          .from('players')
          .select()
          .eq('is_staff', false)
          .order('jersey_number', ascending: true);

      debugPrint('Raw Supabase response: $response');
      debugPrint('Response type: ${response.runtimeType}');
      debugPrint('Response length: ${response.length}');

      _players = (response as List)
          .map((json) => Player.fromJson(json))
          .toList();
      
      debugPrint('Loaded ${_players.length} players from Supabase:');
      for (var i = 0; i < _players.length && i < 10; i++) {
        final p = _players[i];
        debugPrint('  Player $i: "${p.name}" -> category: "${p.teamCategory}", isStaff: ${p.isStaff}');
      }
      
      // Ordina per numero maglia
      _players.sort(_comparePlayersByJerseyNumber);

      debugPrint('Players loaded and sorted successfully!');

      notifyListeners();
    } catch (error) {
      debugPrint('=== ERROR LOADING PLAYERS ===');
      debugPrint('Error type: ${error.runtimeType}');
      debugPrint('Error message: $error');
      
      if (error.toString().contains('table') || error.toString().contains('relation')) {
        debugPrint('Table/relation error - setting empty players list');
        _players = [];
        notifyListeners();
      } else {
        debugPrint('Other error - setting error message');
        _setError('Errore nel caricamento dei giocatori: ${error.toString()}');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadStaff() async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _supabase
          .from('players')
          .select()
          .eq('is_staff', true)
          .order('name', ascending: true);

      _staff = (response as List)
          .map((json) => Player.fromJson(json))
          .toList();

      notifyListeners();
    } catch (error) {
      if (error.toString().contains('table') || error.toString().contains('relation')) {
        _staff = [];
        notifyListeners();
      } else {
        _setError('Errore nel caricamento dello staff: ${error.toString()}');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addPlayer(Player player) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== ADDING PLAYER ===');
        debugPrint('Player: ${player.name}');
        debugPrint('IsStaff: ${player.isStaff}');
        debugPrint('TeamCategory: ${player.teamCategory}');
      }

      final user = _supabase.auth.currentUser;
      if (user == null) {
        if (kDebugMode) {
          debugPrint('ERROR: User not authenticated');
        }
        throw Exception('Utente non autenticato');
      }

      if (kDebugMode) {
        debugPrint('User authenticated: ${user.id}');
        debugPrint('User email: ${user.email}');
      }

      // Esegui test completo Supabase
      if (kDebugMode) {
        await SupabasePlayerTest.testPlayerOperations();
      }

      final playerData = player.copyWith(userId: user.id);
      
      if (kDebugMode) {
        debugPrint('Player data to save: ${playerData.toJson()}');
      }
      
      try {
        if (kDebugMode) {
          debugPrint('Attempting Supabase insert with data: ${playerData.toJson()}');
        }
        
        final response = await _supabase
            .from('players')
            .insert(playerData.toJson())
            .select()
            .single();

        if (kDebugMode) {
          debugPrint('Supabase response: $response');
        }

        final newPlayer = Player.fromJson(response);
        if (kDebugMode) {
          debugPrint('New player created: ${newPlayer.name}, isStaff: ${newPlayer.isStaff}');
        }
        
        if (newPlayer.isStaff) {
          _staff.add(newPlayer);
          _staff.sort((a, b) => a.name.compareTo(b.name));
          if (kDebugMode) {
            debugPrint('Added to staff list. Staff count: ${_staff.length}');
          }
        } else {
          _players.add(newPlayer);
          _players.sort(_comparePlayersByJerseyNumber);
          if (kDebugMode) {
            debugPrint('Added to players list. Players count: ${_players.length}');
          }
        }
        notifyListeners();
        return true;
      } catch (supabaseError) {
        debugPrint('=== SUPABASE ERROR DETAILS ===');
        debugPrint('Error type: ${supabaseError.runtimeType}');
        debugPrint('Error message: $supabaseError');
        debugPrint('Error details: ${supabaseError.toString()}');
        debugPrint('CRITICAL: Player NOT saved to Supabase - falling back to local only!');
        debugPrint('This means data will be lost on app restart!');
        // Fallback: salva solo in memoria locale
        final newPlayer = playerData.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        if (newPlayer.isStaff) {
          _staff.add(newPlayer);
          _staff.sort((a, b) => a.name.compareTo(b.name));
          if (kDebugMode) {
            debugPrint('Added to staff list (local). Staff count: ${_staff.length}');
          }
        } else {
          _players.add(newPlayer);
          _players.sort(_comparePlayersByJerseyNumber);
          if (kDebugMode) {
            debugPrint('Added to players list (local). Players count: ${_players.length}');
          }
        }
        notifyListeners();
        return true;
      }
    } catch (error) {
      _setError('Errore nell\'aggiunta del giocatore: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addStaff(Player staff) async {
    try {
      _setLoading(true);
      _clearError();

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato');
      }

      final staffData = staff.copyWith(userId: user.id, isStaff: true);
      
      try {
        final response = await _supabase
            .from('players')
            .insert(staffData.toJson())
            .select()
            .single();

        final newStaff = Player.fromJson(response);
        _staff.add(newStaff);
        _staff.sort((a, b) => a.name.compareTo(b.name));
        notifyListeners();
        return true;
      } catch (supabaseError) {
        // Fallback: salva solo in memoria locale
        final newStaff = staff.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
          isStaff: true,
        );
        _staff.add(newStaff);
        _staff.sort((a, b) => a.name.compareTo(b.name));
        notifyListeners();
        return true;
      }
    } catch (error) {
      _setError('Errore nell\'aggiunta dello staff: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deletePlayer(String playerId) async {
    try {
      _setLoading(true);
      _clearError();

      try {
        await _supabase
            .from('players')
            .delete()
            .eq('id', playerId);
      } catch (supabaseError) {
        // Continue with local deletion even if Supabase fails
      }

      // Remove from both lists (in case it was moved between staff/player)
      _players.removeWhere((player) => player.id == playerId);
      _staff.removeWhere((staff) => staff.id == playerId);
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'eliminazione del giocatore: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteStaff(String staffId) async {
    try {
      _setLoading(true);
      _clearError();

      try {
        await _supabase
            .from('players')
            .delete()
            .eq('id', staffId);
      } catch (supabaseError) {
        // The error is intentionally ignored.
        // The app will proceed with local deletion even if Supabase fails.
      }

      _staff.removeWhere((staff) => staff.id == staffId);
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'eliminazione dello staff: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updatePlayer(Player player) async {
    try {
      _setLoading(true);
      _clearError();

      await _supabase
          .from('players')
          .update(player.toJson())
          .eq('id', player.id!);

      // Update local list
      if (player.isStaff == true) {
        final index = _staff.indexWhere((p) => p.id == player.id);
        if (index != -1) {
          _staff[index] = player;
          _staff.sort((a, b) => a.name.compareTo(b.name));
        }
      } else {
        final index = _players.indexWhere((p) => p.id == player.id);
        if (index != -1) {
          _players[index] = player;
          _players.sort(_comparePlayersByJerseyNumber);
        }
      }

      notifyListeners();
      return true;
    } catch (error) {
      if (kDebugMode) { // Add this line
        debugPrint('Error updating player: $error'); // Add this line
      } // Add this line
      _setError('Errore nell\'aggiornamento del giocatore: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  List<Player> getPlayersByTeam(String teamCategory) {
    debugPrint('=== PlayerService.getPlayersByTeam("$teamCategory") ===');
    debugPrint('Total players in service: ${_players.length}');
    
    if (_players.isNotEmpty) {
      debugPrint('Sample player categories:');
      for (var i = 0; i < _players.length && i < 5; i++) {
        final p = _players[i];
        debugPrint('  "${p.name}" -> category: "${p.teamCategory}"');
      }
    }
    
    final teamPlayers = _players.where((player) => player.teamCategory == teamCategory).toList();
    
    debugPrint('Found ${teamPlayers.length} players for team "$teamCategory"');
    
    if (kDebugMode) {
      debugPrint('=== PLAYERS FOR TEAM: $teamCategory ===');
      for (var player in teamPlayers) {
        debugPrint('Player: ${player.name}, Jersey: ${player.jerseyNumber}');
      }
      debugPrint('Before sort: ${teamPlayers.map((p) => "${p.name}(${p.jerseyNumber})").join(", ")}');
    }
    
    teamPlayers.sort(_comparePlayersByJerseyNumber);
    
    if (kDebugMode) {
      debugPrint('After sort: ${teamPlayers.map((p) => "${p.name}(${p.jerseyNumber})").join(", ")}');
    }
    
    return teamPlayers;
  }

  List<Player> getStaffByTeam(String teamCategory) {
    return _staff.where((staff) => staff.teamCategory == teamCategory).toList();
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
}