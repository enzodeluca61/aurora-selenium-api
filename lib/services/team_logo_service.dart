import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Servizio per gestire i loghi delle squadre da Supabase Storage
class TeamLogoService extends ChangeNotifier {
  final SupabaseClient _supabase = Supabase.instance.client;

  // Cache per i loghi delle squadre
  final Map<String, String?> _logoCache = {};

  /// Nome del bucket di storage contenente i loghi
  static const String _logosBucket = 'team_logos';

  /// Ottiene l'URL del logo per una squadra specifica
  /// Normalizza il nome della squadra per trovare il file corrispondente
  Future<String?> getTeamLogoUrl(String teamName) async {
    if (teamName.isEmpty) return null;

    // Controlla prima nella cache
    final cacheKey = _normalizeTeamName(teamName);
    if (_logoCache.containsKey(cacheKey)) {
      return _logoCache[cacheKey];
    }

    try {
      // Normalizza il nome della squadra per il filename
      final fileName = _getLogoFileName(teamName);

      if (kDebugMode) {
        debugPrint('🏆 Looking for team logo: $teamName -> $fileName');
      }

      // Prova solo PNG come estensione principale per velocità
      final fullFileName = '$fileName.png';

      try {
        // Ottieni direttamente l'URL pubblico (più veloce)
        final url = _supabase.storage
            .from(_logosBucket)
            .getPublicUrl(fullFileName);

        if (kDebugMode) {
          debugPrint('✅ Generated logo URL: $teamName -> $url');
        }

        // Salva nella cache e ritorna
        _logoCache[cacheKey] = url;
        return url;

      } catch (e) {
        if (kDebugMode) {
          debugPrint('❌ Error generating URL for $teamName: $e');
        }
      }

      // Salva null nella cache per evitare tentativi ripetuti
      _logoCache[cacheKey] = null;
      return null;

    } catch (e) {
      if (kDebugMode) {
        debugPrint('❌ Error getting team logo for $teamName: $e');
      }

      _logoCache[cacheKey] = null;
      return null;
    }
  }

  /// Normalizza il nome della squadra per la chiave di cache
  String _normalizeTeamName(String teamName) {
    return teamName.toLowerCase().trim();
  }

  /// Converte il nome della squadra in un nome file compatibile
  String _getLogoFileName(String teamName) {
    return teamName
        .toLowerCase()
        .trim()
        // Rimuovi caratteri speciali e spazi
        .replaceAll(RegExp(r'[^\w\s]'), '')
        // Sostituisci spazi con underscore
        .replaceAll(RegExp(r'\s+'), '_')
        // Rimuovi underscore multipli
        .replaceAll(RegExp(r'_+'), '_')
        // Rimuovi underscore iniziali e finali
        .replaceAll(RegExp(r'^_|_$'), '');
  }

  /// Precarica i loghi per una lista di squadre
  Future<void> preloadLogos(List<String> teamNames) async {
    final futures = teamNames
        .where((name) => name.isNotEmpty)
        .map((name) => getTeamLogoUrl(name));

    await Future.wait(futures);

    if (kDebugMode) {
      debugPrint('🏆 Preloaded logos for ${teamNames.length} teams');
    }
  }

  /// Pulisce la cache dei loghi
  void clearCache() {
    _logoCache.clear();
    notifyListeners();

    if (kDebugMode) {
      debugPrint('🗑️ Team logo cache cleared');
    }
  }

  /// Ottiene informazioni sulla cache
  Map<String, dynamic> getCacheInfo() {
    final cachedLogos = _logoCache.entries
        .where((entry) => entry.value != null)
        .length;

    return {
      'total_cached': _logoCache.length,
      'logos_found': cachedLogos,
      'logos_not_found': _logoCache.length - cachedLogos,
    };
  }

  /// Metodi di convenienza per squadre specifiche

  /// Ottiene l'URL del logo di Aurora Seriate
  Future<String?> getAuroraLogo() async {
    return await getTeamLogoUrl('Aurora Seriate 1967');
  }

  /// Controlla se una squadra è Aurora Seriate
  bool isAuroraTeam(String teamName) {
    final normalized = teamName.toLowerCase();
    return normalized.contains('aurora') && normalized.contains('seriate');
  }

  /// Ottiene un logo di fallback (icona generica)
  String? getFallbackIcon() {
    // Ritorna null per usare l'icona di default nell'UI
    return null;
  }
}