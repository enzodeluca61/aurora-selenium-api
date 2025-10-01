import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/convocation_model.dart';

class ConvocationService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Convocation> _convocations = [];
  bool _isLoading = false;
  String? _errorMessage;

  ConvocationService() {
    _supabase.auth.onAuthStateChange.listen((data) {
      if (data.session?.user != null) {
        loadConvocations();
      } else {
        _convocations = [];
        notifyListeners();
      }
    });
  }

  List<Convocation> get convocations => _convocations;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadConvocations({String? matchId}) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== LOADING CONVOCATIONS ===');
        debugPrint('Current user: ${_supabase.auth.currentUser?.email}');
        debugPrint('Match ID filter: $matchId');
      }

      var query = _supabase
          .from('convocations')
          .select();

      if (matchId != null) {
        query = query.eq('match_id', matchId);
      }

      final response = await query.order('player_name', ascending: true);

      _convocations = (response as List)
          .map((json) => Convocation.fromJson(json))
          .toList();

      if (kDebugMode) {
        debugPrint('Loaded ${_convocations.length} convocations');
        debugPrint('=======================');
      }

      notifyListeners();
    } catch (error) {
      if (kDebugMode) {
        debugPrint('Error loading convocations: $error');
      }
      if (error.toString().contains('table') || error.toString().contains('relation')) {
        _convocations = [];
        notifyListeners();
      } else {
        _setError('Errore nel caricamento delle convocazioni: ${error.toString()}');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addConvocation(Convocation convocation) async {
    try {
      _setLoading(true);
      _clearError();

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato');
      }

      final convocationData = convocation.copyWith(userId: user.id);
      
      try {
        final response = await _supabase
            .from('convocations')
            .insert(convocationData.toJson())
            .select()
            .single();

        final newConvocation = Convocation.fromJson(response);
        _convocations.add(newConvocation);
      } catch (supabaseError) {
        if (supabaseError.toString().contains('relation "public.convocations" does not exist') ||
            supabaseError.toString().contains('table') ||
            supabaseError.toString().contains('relation')) {
          _setError('Errore: Tabella del database non configurata. Contatta l\'amministratore.');
        }
        else if (supabaseError.toString().contains('policy') || 
                 supabaseError.toString().contains('permission') ||
                 supabaseError.toString().contains('RLS')) {
          _setError('Errore: Permessi del database. Contatta l\'amministratore.');
        }
        
        final newConvocation = convocation.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        _convocations.add(newConvocation);
      }

      _convocations.sort((a, b) => a.playerName.compareTo(b.playerName));
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta della convocazione: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateConvocation(Convocation convocation) async {
    try {
      _setLoading(true);
      _clearError();

      if (kDebugMode) {
        debugPrint('=== UPDATING CONVOCATION ===');
        debugPrint('Convocation ID: ${convocation.id}');
        debugPrint('Player: ${convocation.playerName}');
        debugPrint('Is convocated: ${convocation.isConvocated}');
        debugPrint('============================');
      }

      final response = await _supabase
          .from('convocations')
          .update(convocation.toJson())
          .eq('id', convocation.id!)
          .select()
          .single();

      final updatedConvocation = Convocation.fromJson(response);
      final index = _convocations.indexWhere((c) => c.id == convocation.id);
      if (index != -1) {
        _convocations[index] = updatedConvocation;
        _convocations.sort((a, b) => a.playerName.compareTo(b.playerName));
        notifyListeners();
      }

      return true;
    } catch (error) {
      _setError('Errore nell\'aggiornamento della convocazione: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteConvocation(String convocationId) async {
    try {
      _setLoading(true);
      _clearError();

      await _supabase
          .from('convocations')
          .delete()
          .eq('id', convocationId);

      _convocations.removeWhere((convocation) => convocation.id == convocationId);
      notifyListeners();

      return true;
    } catch (error) {
      _setError('Errore nella cancellazione della convocazione: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  List<Convocation> getConvocationsForMatch(String matchId) {
    return _convocations.where((convocation) => convocation.matchId == matchId).toList();
  }

  List<Convocation> getConvocatedPlayers({String? matchId}) {
    var convocated = _convocations.where((c) => c.isConvocated);
    if (matchId != null) {
      convocated = convocated.where((c) => c.matchId == matchId);
    }
    return convocated.toList();
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

  Future<bool> testSupabaseConnection() async {
    try {
      final user = _supabase.auth.currentUser;
      if (user == null) {
        return false;
      }
      
      try {
        await _supabase
            .from('convocations')
            .select('count(*)')
            .count(CountOption.exact);
        return true;
      } catch (e) {
        try {
          await _supabase
              .from('convocations')
              .insert({
                'player_id': 'TEST',
                'player_name': 'Test Player',
                'is_convocated': false,
                'user_id': user.id,
              })
              .select()
              .single();
          
          await _supabase
              .from('convocations')
              .delete()
              .eq('player_id', 'TEST')
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
}