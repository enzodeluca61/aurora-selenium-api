import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/team_model.dart';

class TeamService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Team> _teams = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Team> get teams => _teams;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadTeams() async {
    try {
      _setLoading(true);
      _clearError();

      // Carica squadre dalla tabella teams
      final response = await _supabase
          .from('teams')
          .select('*')
          .order('sort_order', ascending: true)
          .order('category', ascending: true);

      _teams = (response as List)
          .map((json) => Team.fromJson(json))
          .toList();

      notifyListeners();
    } catch (error) {
      if (error.toString().contains('table') || error.toString().contains('relation')) {
        // Fallback con categorie standard se la tabella non esiste
        _teams = [
          Team(id: '1', category: 'U12', sortOrder: 1),
          Team(id: '2', category: 'U14', sortOrder: 2),
          Team(id: '3', category: 'U15', sortOrder: 3),
          Team(id: '4', category: 'U16', sortOrder: 4),
          Team(id: '5', category: 'U17', sortOrder: 5),
          Team(id: '6', category: 'U18', sortOrder: 6),
          Team(id: '7', category: 'U19', sortOrder: 7),
          Team(id: '8', category: 'Prima Squadra', sortOrder: 8),
        ];
        notifyListeners();
      } else {
        _setError('Errore nel caricamento delle squadre: ${error.toString()}');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addTeam(Team team) async {
    try {
      _setLoading(true);
      _clearError();

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato');
      }

      // Calcola il sort_order come ultimo + 1
      int nextSortOrder = 0;
      if (_teams.isNotEmpty) {
        nextSortOrder = _teams.map((t) => t.sortOrder).reduce((max, current) => current > max ? current : max) + 1;
      }

      final teamData = team.copyWith(
        userId: user.id,
        sortOrder: nextSortOrder,
      );
      
      try {
        final response = await _supabase
            .from('teams')
            .insert(teamData.toJson())
            .select()
            .single();

        final newTeam = Team.fromJson(response);
        _teams.add(newTeam);
      } catch (supabaseError) {
        // Fallback: salva solo in memoria locale
        final newTeam = teamData.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        _teams.add(newTeam);
      }

      _teams.sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta della squadra: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteTeam(String teamId) async {
    try {
      _setLoading(true);
      _clearError();

      await _supabase
          .from('teams')
          .delete()
          .eq('id', teamId);

      _teams.removeWhere((team) => team.id == teamId);
      notifyListeners();

      return true;
    } catch (error) {
      _setError('Errore nella cancellazione della squadra: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
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

  Future<bool> updateTeamsSortOrder(List<Team> reorderedTeams) async {
    try {
      _setLoading(true);
      _clearError();

      // Aggiorna l'ordine locale prima
      _teams = reorderedTeams;
      notifyListeners();

      // Aggiorna ogni squadra con il nuovo sortOrder
      for (int i = 0; i < reorderedTeams.length; i++) {
        final team = reorderedTeams[i].copyWith(sortOrder: i);
        
        try {
          await _supabase
              .from('teams')
              .update({'sort_order': i})
              .eq('id', team.id!);
          
          // Aggiorna anche la lista locale
          _teams[i] = team;
        } catch (supabaseError) {
          // Continua con le altre anche in caso di errore
        }
      }

      return true;
    } catch (error) {
      _setError('Errore nell\'aggiornamento dell\'ordine: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }
}