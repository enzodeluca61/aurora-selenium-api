import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/match_model.dart';
import '../models/team_model.dart';
import '../services/instagram_results_service.dart';

class InstagramResultsPreviewWidget extends StatefulWidget {
  final List<Match> matches;
  final DateTime startDate;
  final DateTime endDate;
  final List<Team>? teams;

  const InstagramResultsPreviewWidget({
    super.key,
    required this.matches,
    required this.startDate,
    required this.endDate,
    this.teams,
  });

  @override
  State<InstagramResultsPreviewWidget> createState() => _InstagramResultsPreviewWidgetState();
}

class _InstagramResultsPreviewWidgetState extends State<InstagramResultsPreviewWidget> {
  bool isGenerating = false;
  Uint8List? previewImage;

  /// Mostra l'anteprima del PDF
  Future<void> _showPreview() async {
    if (isGenerating) return;

    setState(() {
      isGenerating = true;
    });

    try {
      final imageBytes = await InstagramResultsService.generateResultsJpg(
        matches: widget.matches,
        startDate: widget.startDate,
        endDate: widget.endDate,
        teams: widget.teams,
      );

      if (mounted) {
        setState(() {
          previewImage = imageBytes;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Errore nella generazione dell\'immagine: ${e.toString()}'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          isGenerating = false;
        });
      }
    }
  }

  /// Conta le partite nella settimana
  int _getMatchesCount() {
    return widget.matches
        .where((match) =>
            match.date.isAfter(widget.startDate.subtract(const Duration(days: 1))) &&
            match.date.isBefore(widget.endDate.add(const Duration(days: 1))))
        .length;
  }

  @override
  Widget build(BuildContext context) {
    final matchesCount = _getMatchesCount();
    final startDateStr = DateFormat('dd/MM').format(widget.startDate);
    final endDateStr = DateFormat('dd/MM').format(widget.endDate);

    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(top: 580.0, left: 16, right: 16, bottom: 16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF1E3A8A),
            const Color(0xFF3B82F6),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(
                    Icons.image,
                    color: Colors.white,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Anteprima Risultati Instagram',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            // Informazioni periodo
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.date_range,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Periodo: $startDateStr - $endDateStr',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Statistiche partite
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.sports_soccer,
                    color: Colors.white70,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Partite programmate: $matchesCount',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            // Pulsante anteprima
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: matchesCount > 0 && !isGenerating ? _showPreview : null,
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFF1E3A8A),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 2,
                ),
                child: isGenerating
                    ? const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF1E3A8A)),
                            ),
                          ),
                          SizedBox(width: 12),
                          Text(
                            'Generazione immagine...',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      )
                    : const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.visibility, size: 20),
                          SizedBox(width: 8),
                          Text(
                            'Mostra Anteprima',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
            if (matchesCount == 0)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  'Nessuna partita programmata nel periodo selezionato',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.7),
                    fontSize: 12,
                    fontStyle: FontStyle.italic,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
            // Anteprima immagine
            if (previewImage != null) ...[
              const SizedBox(height: 20),
              Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 8,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.memory(
                    previewImage!,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}