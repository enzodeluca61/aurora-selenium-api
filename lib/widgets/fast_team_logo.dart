import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// Widget ultrarapido per i loghi delle squadre
/// Genera direttamente l'URL senza verifiche e lascia gestire gli errori al sistema
class FastTeamLogo extends StatelessWidget {
  final String teamName;
  final double size;
  final Color? fallbackColor;

  const FastTeamLogo({
    super.key,
    required this.teamName,
    this.size = 20.0,
    this.fallbackColor,
  });

  /// Genera l'URL diretto del logo senza verifiche
  String _generateLogoUrl(String teamName) {
    var fileName = teamName
        .toLowerCase()
        .trim()
        .replaceAll(RegExp(r'[^\w\s]'), '')
        .replaceAll(RegExp(r'\s+'), '_')
        .replaceAll(RegExp(r'_+'), '_')
        .replaceAll(RegExp(r'^_|_$'), '');

    // Gestione speciale per SQ.A e SQ.B (rimuove lo spazio prima della lettera)
    fileName = fileName
        .replaceAll(RegExp(r'sq_([ab])'), 'sq-\$1');

    // URL base di Supabase per il bucket pubblico
    // NOTA: Il bucket 'loghi' contiene i loghi delle squadre
    const baseUrl = 'https://hkhuabfxjlcidlodbiru.supabase.co/storage/v1/object/public/loghi';
    return '$baseUrl/$fileName.png';
  }

  @override
  Widget build(BuildContext context) {
    if (teamName.isEmpty) {
      return Icon(
        Icons.sports_soccer,
        size: size,
        color: fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
      );
    }

    final logoUrl = _generateLogoUrl(teamName);

    if (kDebugMode) {
      debugPrint('🚀 Fast logo URL: $teamName -> $logoUrl');
    }

    return Image.network(
      logoUrl,
      height: size,
      fit: BoxFit.contain,
      cacheHeight: (size * 2).round(),
      errorBuilder: (context, error, stackTrace) {
        // Fallback silenzioso in caso di errore (non loggare errori HTTP 400)
        return Icon(
          Icons.sports_soccer,
          size: size,
          color: fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
        );
      },
      loadingBuilder: (context, child, loadingProgress) {
        if (loadingProgress == null) {
          return child;
        }
        // Mostra icona durante il caricamento
        return Icon(
          Icons.sports_soccer,
          size: size,
          color: fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
        );
      },
    );
  }
}