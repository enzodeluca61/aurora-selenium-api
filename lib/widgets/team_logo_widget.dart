import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/team_logo_service.dart';

/// Widget per mostrare il logo di una squadra
/// Carica il logo da Supabase Storage o mostra un'icona di fallback
class TeamLogoWidget extends StatefulWidget {
  final String teamName;
  final double size;
  final Color? fallbackColor;
  final IconData? fallbackIcon;

  const TeamLogoWidget({
    super.key,
    required this.teamName,
    this.size = 24.0,
    this.fallbackColor,
    this.fallbackIcon = Icons.sports_soccer,
  });

  @override
  State<TeamLogoWidget> createState() => _TeamLogoWidgetState();
}

class _TeamLogoWidgetState extends State<TeamLogoWidget> {
  String? _logoUrl;
  bool _isLoading = true;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _loadLogo();
  }

  @override
  void didUpdateWidget(TeamLogoWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.teamName != widget.teamName) {
      _loadLogo();
    }
  }

  Future<void> _loadLogo() async {
    if (widget.teamName.isEmpty) {
      setState(() {
        _isLoading = false;
        _hasError = true;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _hasError = false;
    });

    try {
      final logoService = context.read<TeamLogoService>();
      final logoUrl = await logoService.getTeamLogoUrl(widget.teamName);

      if (mounted) {
        setState(() {
          _logoUrl = logoUrl;
          _isLoading = false;
          _hasError = logoUrl == null;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoading = false;
          _hasError = true;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      // Mostra immediatamente l'icona di fallback durante il caricamento per velocità
      return Icon(
        widget.fallbackIcon,
        size: widget.size,
        color: widget.fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
      );
    }

    if (_hasError || _logoUrl == null || _logoUrl!.isEmpty) {
      // Mostra icona di fallback
      return Icon(
        widget.fallbackIcon,
        size: widget.size,
        color: widget.fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
      );
    }

    // Mostra il logo della squadra
    return ClipOval(
      child: Image.network(
        _logoUrl!,
        width: widget.size,
        height: widget.size,
        fit: BoxFit.cover,
        // Cache delle immagini per velocità
        cacheWidth: (widget.size * 2).round(),
        cacheHeight: (widget.size * 2).round(),
        errorBuilder: (context, error, stackTrace) {
          if (kDebugMode) {
            debugPrint('❌ Failed to load image: $_logoUrl - $error');
          }
          // Fallback in caso di errore nel caricamento dell'immagine
          return Icon(
            widget.fallbackIcon,
            size: widget.size,
            color: widget.fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
          );
        },
        loadingBuilder: (context, child, loadingProgress) {
          if (loadingProgress == null) {
            if (kDebugMode) {
              debugPrint('✅ Logo loaded successfully: $_logoUrl');
            }
            return child;
          }
          // Mostra icona durante il caricamento per evitare spinner
          return Icon(
            widget.fallbackIcon,
            size: widget.size,
            color: widget.fallbackColor ?? Colors.grey.withValues(alpha: 0.7),
          );
        },
      ),
    );
  }
}

/// Widget ottimizzato per mostrare loghi di squadre nella lista risultati
class ResultTeamLogo extends StatelessWidget {
  final String teamName;
  final Color? color;

  const ResultTeamLogo({
    super.key,
    required this.teamName,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    return TeamLogoWidget(
      teamName: teamName,
      size: 20.0,
      fallbackColor: color,
      fallbackIcon: Icons.sports_soccer,
    );
  }
}