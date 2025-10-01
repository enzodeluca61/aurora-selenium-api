import 'package:supabase_flutter/supabase_flutter.dart';

class SupabaseTest {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<Map<String, dynamic>> testConnection() async {
    final results = <String, dynamic>{};
    
    try {
      // Test basic connectivity
      results['connectivity'] = 'OK';
      results['user'] = _supabase.auth.currentUser?.id ?? 'Not authenticated';
      
      // Test teams table
      try {
        final teamsResponse = await _supabase.from('teams').select().limit(1);
        results['teams_table'] = 'OK (${teamsResponse.length} records found)';
      } catch (e) {
        results['teams_table'] = 'ERROR: $e';
      }
      
      // Test trainings table
      try {
        final trainingsResponse = await _supabase.from('trainings').select().limit(1);
        results['trainings_table'] = 'OK (${trainingsResponse.length} records found)';
      } catch (e) {
        results['trainings_table'] = 'ERROR: $e';
      }
      
      // Test players table
      try {
        final playersResponse = await _supabase.from('players').select().limit(1);
        results['players_table'] = 'OK (${playersResponse.length} records found)';
      } catch (e) {
        results['players_table'] = 'ERROR: $e';
      }
      
      // Test fields table
      try {
        final fieldsResponse = await _supabase.from('fields').select().limit(1);
        results['fields_table'] = 'OK (${fieldsResponse.length} records found)';
      } catch (e) {
        results['fields_table'] = 'ERROR: $e';
      }
      
    } catch (e) {
      results['connectivity'] = 'ERROR: $e';
    }
    
    return results;
  }

  
}