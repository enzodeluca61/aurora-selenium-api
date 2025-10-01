import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SupabasePlayerTest {
  static final SupabaseClient _supabase = Supabase.instance.client;

  static Future<void> testPlayerOperations() async {
    if (kDebugMode) {
      debugPrint('=== SUPABASE PLAYER TEST ===');
    }

    try {
      // Test 1: Check authentication
      final user = _supabase.auth.currentUser;
      if (kDebugMode) {
        debugPrint('Current user: ${user?.email ?? 'NOT AUTHENTICATED'}');
        debugPrint('User ID: ${user?.id ?? 'NULL'}');
      }

      if (user == null) {
        debugPrint('ERROR: User not authenticated - cannot test');
        return;
      }

      // Test 2: Check if players table exists and its structure
      try {
        final countResult = await _supabase.from('players').select('count').count();
        if (kDebugMode) {
          debugPrint('Players table exists - current count: $countResult');
        }

        // Try to get one record to see the structure
        try {
          final sample = await _supabase.from('players').select().limit(1);
          if (kDebugMode) {
            debugPrint('Sample record structure: $sample');
          }
        } catch (e) {
          if (kDebugMode) {
            debugPrint('No records yet, but table exists');
          }
        }
      } catch (tableError) {
        if (kDebugMode) {
          debugPrint('ERROR: Players table issue: $tableError');
          debugPrint('This might mean:');
          debugPrint('1. Table does not exist');
          debugPrint('2. RLS policies are blocking access');  
          debugPrint('3. Wrong table structure');
        }
        return;
      }

      // Test 3: Try to insert a test player
      final testPlayerData = {
        'name': 'Test Player ${DateTime.now().millisecondsSinceEpoch}',
        'position': 'Test Position',
        'jersey_number': 99,
        'team_category': 'Test Team',
        'is_staff': false,
        'user_id': user.id,
        'created_at': DateTime.now().toIso8601String(),
      };

      if (kDebugMode) {
        debugPrint('Attempting to insert test player: $testPlayerData');
      }

      try {
        final response = await _supabase
            .from('players')
            .insert(testPlayerData)
            .select()
            .single();

        if (kDebugMode) {
          debugPrint('SUCCESS: Test player inserted: $response');
        }

        // Test 4: Try to delete the test player
        final playerId = response['id'];
        await _supabase.from('players').delete().eq('id', playerId);
        
        if (kDebugMode) {
          debugPrint('SUCCESS: Test player deleted');
        }

      } catch (insertError) {
        if (kDebugMode) {
          debugPrint('ERROR: Failed to insert test player: $insertError');
          debugPrint('Error type: ${insertError.runtimeType}');
        }
      }

    } catch (generalError) {
      if (kDebugMode) {
        debugPrint('GENERAL ERROR in test: $generalError');
      }
    }

    if (kDebugMode) {
      debugPrint('=== TEST COMPLETED ===');
    }
  }
}