import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/player_model.dart';
import '../models/attendance_model.dart';

class AttendanceService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Player> _players = [];
    final Map<String, List<Attendance>> _attendanceByDate = {};
  bool _isLoading = false;
  String? _errorMessage;

  List<Player> get players => _players;
  Map<String, List<Attendance>> get attendanceByDate => _attendanceByDate;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadPlayers() async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _supabase
          .from('players')
          .select()
          .order('name', ascending: true);

      _players = (response as List)
          .map((json) => Player.fromJson(json))
          .toList();

      notifyListeners();
    } catch (error) {
      _setError('Errore nel caricamento dei giocatori: ${error.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<void> loadAttendanceForMonth(DateTime month) async {
    try {
      _setLoading(true);
      _clearError();

      final startOfMonth = DateTime(month.year, month.month, 1);
      final endOfMonth = DateTime(month.year, month.month + 1, 0);

      final response = await _supabase
          .from('attendance')
          .select()
          .gte('date', startOfMonth.toIso8601String().split('T')[0])
          .lte('date', endOfMonth.toIso8601String().split('T')[0]);

      final attendanceList = (response as List)
          .map((json) => Attendance.fromJson(json))
          .toList();

      // Group attendance by date
      _attendanceByDate.clear();
      for (final attendance in attendanceList) {
        final dateKey = attendance.date.toIso8601String().split('T')[0];
        _attendanceByDate[dateKey] = _attendanceByDate[dateKey] ?? [];
        _attendanceByDate[dateKey]!.add(attendance);
      }

      notifyListeners();
    } catch (error) {
      _setError('Errore nel caricamento delle presenze: ${error.toString()}');
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> addPlayer(Player player) async {
    try {
      _setLoading(true);
      _clearError();

      final response = await _supabase
          .from('players')
          .insert(player.toJson())
          .select()
          .single();

      final newPlayer = Player.fromJson(response);
      _players.add(newPlayer);
      _players.sort((a, b) => a.name.compareTo(b.name));
      
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta del giocatore: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deletePlayer(String playerId) async {
    try {
      _setLoading(true);
      _clearError();

      await _supabase
          .from('players')
          .delete()
          .eq('id', playerId);

      _players.removeWhere((player) => player.id == playerId);
      
      // Also remove related attendance records from local cache
      for (final attendanceList in _attendanceByDate.values) {
        attendanceList.removeWhere((attendance) => attendance.playerId == playerId);
      }
      
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'eliminazione del giocatore: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> saveAttendance(DateTime date, String playerId, AttendanceStatus status, String? notes) async {
    try {
      _setLoading(true);
      _clearError();

      final dateKey = date.toIso8601String().split('T')[0];
      
      // Check if attendance already exists
      final existingAttendance = getAttendanceForPlayerOnDate(date, playerId);
      
      if (existingAttendance != null) {
        // Update existing attendance
        await _supabase
            .from('attendance')
            .update({
              'status': status.code,
              'notes': notes,
            })
            .eq('id', existingAttendance.id!);

        // Update local data
        final updatedAttendance = Attendance(
          id: existingAttendance.id,
          playerId: playerId,
          date: date,
          status: status,
          notes: notes,
        );

        _attendanceByDate[dateKey] = _attendanceByDate[dateKey]!
            .map((a) => a.id == existingAttendance.id ? updatedAttendance : a)
            .toList();
      } else {
        // Create new attendance
        final newAttendance = Attendance(
          playerId: playerId,
          date: date,
          status: status,
          notes: notes,
        );

        final response = await _supabase
            .from('attendance')
            .insert(newAttendance.toJson(includeId: false))
            .select()
            .single();

        final savedAttendance = Attendance.fromJson(response);
        _attendanceByDate[dateKey] = _attendanceByDate[dateKey] ?? [];
        _attendanceByDate[dateKey]!.add(savedAttendance);
      }

      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nel salvataggio della presenza: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Attendance? getAttendanceForPlayerOnDate(DateTime date, String playerId) {
    final dateKey = date.toIso8601String().split('T')[0];
    final attendanceList = _attendanceByDate[dateKey] ?? [];
    
    try {
      return attendanceList.firstWhere((a) => a.playerId == playerId);
    } catch (e) {
      return null;
    }
  }

  Map<String, int> getAttendanceStatsForPlayer(String playerId, DateTime month) {
    final stats = <String, int>{};
    for (final status in AttendanceStatus.values) {
      stats[status.code] = 0;
    }

    for (final attendanceList in _attendanceByDate.values) {
      for (final attendance in attendanceList) {
        if (attendance.playerId == playerId && 
            attendance.date.month == month.month && 
            attendance.date.year == month.year) {
          stats[attendance.status.code] = (stats[attendance.status.code] ?? 0) + 1;
        }
      }
    }

    return stats;
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