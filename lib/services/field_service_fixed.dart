import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../models/field_model.dart';

class FieldService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;
  List<Field> _fields = [];
  bool _isLoading = false;
  String? _errorMessage;

  List<Field> get fields => _fields;
  bool get isLoading => _isLoading;
  String? get errorMessage => _errorMessage;

  Future<void> loadFields() async {
    try {
      _setLoading(true);
      _clearError();

      try {
        // Prima prova a caricare dalla tabella fields
        final response = await _supabase
            .from('fields')
            .select()
            .order('name', ascending: true);

        _fields = (response as List)
            .map((json) => _mapSupabaseToField(json))
            .toList();

      } catch (supabaseError) {
        // Se fallisce, usa campi di default
        _fields = _getDefaultFields();
      }

      notifyListeners();
    } catch (error) {
      _fields = _getDefaultFields();
      notifyListeners();
    } finally {
      _setLoading(false);
    }
  }

  // Mappa i dati Supabase al modello Field Flutter
  Field _mapSupabaseToField(Map<String, dynamic> json) {
    return Field(
      id: json['id']?.toString(),
      name: json['name'] ?? '',
      address: json['notes'] ?? '', // Usa notes come address temporaneo
      code: _generateCodeFromName(json['name'] ?? ''),
    );
  }

  // Genera un codice dal nome del campo
  String _generateCodeFromName(String name) {
    if (name.isEmpty) return 'CAM';
    
    // Estrae le prime lettere delle parole
    final words = name.split(' ');
    if (words.length >= 2) {
      return words.take(2).map((w) => w.isNotEmpty ? w[0].toUpperCase() : '').join('');
    } else {
      return name.length >= 3 ? name.substring(0, 3).toUpperCase() : name.toUpperCase();
    }
  }

  // Campi di default per l'app
  List<Field> _getDefaultFields() {
    return [
      Field(
        id: '1',
        name: 'Campo A - Principale',
        address: 'Via dello Sport, 1 - Seriate',
        code: 'CA',
      ),
      Field(
        id: '2',
        name: 'Campo B - Allenamento',
        address: 'Via dello Sport, 1 - Seriate',
        code: 'CB',
      ),
      Field(
        id: '3',
        name: 'Campo C - Settore Giovanile',
        address: 'Via dello Sport, 1 - Seriate',
        code: 'CC',
      ),
      Field(
        id: '4',
        name: 'Palestra Coperta',
        address: 'Via dello Sport, 1 - Seriate',
        code: 'PC',
      ),
      Field(
        id: '5',
        name: 'Campo Sintetico',
        address: 'Via dello Sport, 1 - Seriate',
        code: 'CS',
      ),
    ];
  }

  Future<bool> addField(Field field) async {
    try {
      _setLoading(true);
      _clearError();

      // Genera un ID temporaneo se non presente
      final newField = field.copyWith(
        id: field.id ?? DateTime.now().millisecondsSinceEpoch.toString(),
      );

      try {
        // Prova a salvare su Supabase
        final user = _supabase.auth.currentUser;
        final fieldData = {
          'name': newField.name,
          'notes': newField.address,
          'type': 'Campo sportivo',
          'available': true,
          'lighting': true,
          'user_id': user?.id,
        };
        
        final response = await _supabase
            .from('fields')
            .insert(fieldData)
            .select()
            .single();

        final savedField = _mapSupabaseToField(response);
        _fields.add(savedField);
        
      } catch (supabaseError) {
        // Fallback: salva solo in memoria locale
        _fields.add(newField);
      }

      _fields.sort((a, b) => a.name.compareTo(b.name));
      notifyListeners();
      return true;
    } catch (error) {
      _setError('Errore nell\'aggiunta del campo: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> updateField(Field field) async {
    try {
      _setLoading(true);
      _clearError();

      try {
        // Prova ad aggiornare su Supabase
        final fieldData = {
          'name': field.name,
          'notes': field.address,
          'type': 'Campo sportivo',
        };
        
        final response = await _supabase
            .from('fields')
            .update(fieldData)
            .eq('id', field.id!)
            .select()
            .single();

        final updatedField = _mapSupabaseToField(response);
        final index = _fields.indexWhere((f) => f.id == field.id);
        if (index != -1) {
          _fields[index] = updatedField;
          _fields.sort((a, b) => a.name.compareTo(b.name));
          notifyListeners();
        }
        
      } catch (supabaseError) {
        // Fallback: aggiorna solo in memoria locale
        final index = _fields.indexWhere((f) => f.id == field.id);
        if (index != -1) {
          _fields[index] = field;
          _fields.sort((a, b) => a.name.compareTo(b.name));
          notifyListeners();
        }
      }

      return true;
    } catch (error) {
      _setError('Errore nell\'aggiornamento del campo: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  Future<bool> deleteField(String fieldId) async {
    try {
      _setLoading(true);
      _clearError();

      try {
        // Prova a eliminare da Supabase
        await _supabase
            .from('fields')
            .delete()
            .eq('id', fieldId);
            
      } catch (supabaseError) {
        // The error is intentionally ignored.
        // The app will proceed with local deletion even if Supabase fails.
      }

      // Rimuovi dalla lista locale in ogni caso
      _fields.removeWhere((field) => field.id == fieldId);
      notifyListeners();

      return true;
    } catch (error) {
      _setError('Errore nella cancellazione del campo: ${error.toString()}');
      return false;
    } finally {
      _setLoading(false);
    }
  }

  // Inizializza i campi di default se il database è vuoto
  Future<void> initializeDefaultFields() async {
    if (_fields.isEmpty) {
      _fields = _getDefaultFields();
      notifyListeners();
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
}