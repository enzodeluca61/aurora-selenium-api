import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/training_model.dart';

class TrainingService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Training> _trainings = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Training> get trainings => _trainings;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadTrainings({DateTime? weekStart}) async {
    try {
      _setLoading(true);
      _clearError();

      final response = weekStart != null
          ? await _supabase
              .from('trainings')
              .select()
              .eq('week_start', weekStart.toIso8601String().split('T')[0])
              .order('weekday', ascending: true)
          : await _supabase
              .from('trainings')
              .select()
              .order('week_start', ascending: false)
              .order('weekday', ascending: true);

      _trainings = (response as List)
          .map((json) => Training.fromJson(json))
          .toList();

      notifyListeners();
    } catch (error) {
      if (error.toString().contains('table') || error.toString().contains('relation')) {
        _trainings = [];
        notifyListeners();
      } else {
        _setError('Errore nel caricamento degli allenamenti: ${error.toString()}');
      }
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addTraining(Training training) async {
    try {
      _setLoading(true);
      _clearError();

      final user = _supabase.auth.currentUser;
      if (user == null) {
        throw Exception('Utente non autenticato');
      }

      // Non specificare ID, lascia che il database lo generi automaticamente
      final trainingData = training.copyWith(
        userId: user.id,
        clearId: true, // Rimuovi qualsiasi ID esistente
      );
      
      try {
        if (kDebugMode) {
          debugPrint('Attempting to upsert training to Supabase: ${trainingData.toJson()}');
        }
        
        // Prima controlla se esiste già un record con questi criteri
        final existingRecords = await _supabase
            .from('trainings')
            .select('id')
            .eq('team_category', trainingData.teamCategory)
            .eq('weekday', trainingData.weekday)
            .eq('week_start', trainingData.weekStart.toIso8601String().split('T')[0]);
        
        dynamic response;
        if (existingRecords.isNotEmpty) {
          // UPDATE del record esistente
          final existingId = existingRecords.first['id'];
          response = await _supabase
              .from('trainings')
              .update(trainingData.toJson())
              .eq('id', existingId)
              .select()
              .single();
        } else {
          // INSERT di nuovo record
          response = await _supabase
              .from('trainings')
              .insert(trainingData.toJson())
              .select()
              .single();
        }
        
        if (kDebugMode) {
          debugPrint('Training upserted successfully to Supabase: $response');
        }
        
        final resultTraining = Training.fromJson(response);
        
        // Trova se esiste già nella lista locale
        final existingIndex = _trainings.indexWhere((t) => 
            t.teamCategory == resultTraining.teamCategory &&
            t.weekday == resultTraining.weekday &&
            t.weekStart.year == resultTraining.weekStart.year &&
            t.weekStart.month == resultTraining.weekStart.month &&
            t.weekStart.day == resultTraining.weekStart.day);
        
        if (existingIndex != -1) {
          // Aggiorna quello esistente
          _trainings[existingIndex] = resultTraining;
        } else {
          // Aggiungi nuovo
          _trainings.add(resultTraining);
        }
      } catch (supabaseError) {
        if (kDebugMode) {
          debugPrint('=== SUPABASE ERROR IN TRAINING SAVE ===');
          debugPrint('Error type: ${supabaseError.runtimeType}');
          debugPrint('Error message: $supabaseError');
          debugPrint('Training data: ${trainingData.toJson()}');
          debugPrint('Falling back to local save');
        }
        
        // Fallback: salva solo in memoria locale
        final newTraining = training.copyWith(
          id: DateTime.now().millisecondsSinceEpoch.toString(),
        );
        _trainings.add(newTraining);
      }

      _trainings.sort((a, b) {
        int weekCompare = b.weekStart.compareTo(a.weekStart);
        if (weekCompare != 0) return weekCompare;
        return a.weekday.compareTo(b.weekday);
      });
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta dell\'allenamento: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateTraining(Training training) async {
    try {
      _setLoading(true);
      _clearError();

      try {
        final response = await _supabase
            .from('trainings')
            .update(training.toJson())
            .eq('id', training.id!)
            .select()
            .single();

        final updatedTraining = Training.fromJson(response);
        final index = _trainings.indexWhere((t) => t.id == training.id);
        if (index != -1) {
          _trainings[index] = updatedTraining;
          _trainings.sort((a, b) {
            int weekCompare = b.weekStart.compareTo(a.weekStart);
            if (weekCompare != 0) return weekCompare;
            return a.weekday.compareTo(b.weekday);
          });
          notifyListeners();
        }
      } catch (supabaseError) {
        // Fallback: aggiorna solo in memoria locale
        final index = _trainings.indexWhere((t) => t.id == training.id);
        if (index != -1) {
          _trainings[index] = training;
          _trainings.sort((a, b) {
            int weekCompare = b.weekStart.compareTo(a.weekStart);
            if (weekCompare != 0) return weekCompare;
            return a.weekday.compareTo(b.weekday);
          });
          notifyListeners();
        }
      }

      return true;
    } catch (error) {
      _setError('Errore nell\'aggiornamento dell\'allenamento: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteTraining(String trainingId) async {
    try {
      _setLoading(true);
      _clearError();

      try {
        await _supabase
            .from('trainings')
            .delete()
            .eq('id', trainingId);
      } catch (supabaseError) {
        // The error is intentionally ignored.
      }

      _trainings.removeWhere((training) => training.id == trainingId);
      notifyListeners();

      return true;
    } catch (error) {
      _setError('Errore nella cancellazione dell\'allenamento: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  List<Training> getTrainingsForWeek(DateTime weekStart) {
    return _trainings.where((training) {
      return training.weekStart.year == weekStart.year &&
             training.weekStart.month == weekStart.month &&
             training.weekStart.day == weekStart.day;
    }).toList();
  }

  Training? getTraining(String teamCategory, int weekday, DateTime weekStart) {
    try {
      return _trainings.firstWhere(
        (training) => 
            training.teamCategory == teamCategory &&
            training.weekday == weekday &&
            training.weekStart.year == weekStart.year &&
            training.weekStart.month == weekStart.month &&
            training.weekStart.day == weekStart.day,
      );
    } catch (e) {
      return null;
    }
  }

  bool hasTraining(String teamCategory, int weekday, DateTime weekStart) {
    return getTraining(teamCategory, weekday, weekStart) != null;
  }

  Future<bool> copyWeekTrainings(DateTime fromWeek, DateTime toWeek) async {
    try {
      _setLoading(true);
      _clearError();

      final weekTrainings = getTrainingsForWeek(fromWeek);
      
      if (kDebugMode) {
        debugPrint('=== COPYING WEEK TRAININGS ===');
        debugPrint('From week: $fromWeek');
        debugPrint('To week: $toWeek');
        debugPrint('Found ${weekTrainings.length} trainings to copy');
      }
      
      for (final training in weekTrainings) {
        if (kDebugMode) {
          debugPrint('Copying training: ${training.teamCategory} ${training.weekday}');
        }
        
        final newTraining = training.copyWith(
          clearId: true, // Rimuovi ID per nuovo record
          weekStart: toWeek,
        );
        
        final success = await addTraining(newTraining);
        if (kDebugMode) {
          debugPrint('Training copy result: $success');
        }
      }

      if (kDebugMode) {
        debugPrint('Week copy completed');
      }
      return true;
    } catch (error) {
      _setError('Errore nella copia della settimana: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> copyWeekRangeTrainings(DateTime fromWeekStart, DateTime fromWeekEnd, DateTime toWeekStart) async {
    try {
      _setLoading(true);
      _clearError();

      // Calcola quante settimane ci sono nel range
      final weeksDifference = fromWeekEnd.difference(fromWeekStart).inDays ~/ 7;
      
      DateTime currentFromWeek = fromWeekStart;
      DateTime currentToWeek = toWeekStart;
      
      // Copia settimana per settimana nel range
      for (int i = 0; i <= weeksDifference; i++) {
        final weekTrainings = getTrainingsForWeek(currentFromWeek);
        
        for (final training in weekTrainings) {
          final newTraining = training.copyWith(
            clearId: true, // Rimuovi ID per nuovo record
            weekStart: currentToWeek,
          );
          
          await addTraining(newTraining);
        }
        
        // Vai alla settimana successiva
        currentFromWeek = currentFromWeek.add(const Duration(days: 7));
        currentToWeek = currentToWeek.add(const Duration(days: 7));
      }

      return true;
    } catch (error) {
      _setError('Errore nella copia del range di settimane: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteWeekTrainings(DateTime weekStart) async {
    try {
      _setLoading(true);
      _clearError();

      final weekTrainings = getTrainingsForWeek(weekStart);
      
      if (weekTrainings.isEmpty) {
        return true; // Niente da cancellare
      }

      // Elimina da Supabase
      try {
        await _supabase
            .from('trainings')
            .delete()
            .eq('week_start', weekStart.toIso8601String().split('T')[0]);
      } catch (supabaseError) {
        // Continua anche se fallisce su Supabase
      }

      // Rimuovi dalla lista locale
      _trainings.removeWhere((training) => 
          training.weekStart.year == weekStart.year &&
          training.weekStart.month == weekStart.month &&
          training.weekStart.day == weekStart.day);
      
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nella cancellazione della settimana: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  DateTime getWeekStart(DateTime date) {
    // Trova il lunedì della settimana
    final dayOfWeek = date.weekday; // 1 = lunedì, 7 = domenica
    return date.subtract(Duration(days: dayOfWeek - 1));
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