import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/result_model.dart';

class ManualScoreDialog extends StatefulWidget {
  final MatchResult match;

  const ManualScoreDialog({
    super.key,
    required this.match,
  });

  @override
  State<ManualScoreDialog> createState() => _ManualScoreDialogState();
}

class _ManualScoreDialogState extends State<ManualScoreDialog> {
  late TextEditingController _homeScoreController;
  late TextEditingController _awayScoreController;
  final _formKey = GlobalKey<FormState>();

  @override
  void initState() {
    super.initState();
    _homeScoreController = TextEditingController(
      text: widget.match.homeScore.toString(),
    );
    _awayScoreController = TextEditingController(
      text: widget.match.awayScore.toString(),
    );
  }

  @override
  void dispose() {
    _homeScoreController.dispose();
    _awayScoreController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isAuroraHome = widget.match.homeTeam.toLowerCase().contains('aurora');
    final isAuroraAway = widget.match.awayTeam.toLowerCase().contains('aurora');

    return AlertDialog(
      title: const Text(
        'Inserisci Risultato',
        style: TextStyle(
          fontWeight: FontWeight.bold,
          color: Color(0xFF1E3A8A),
        ),
      ),
      content: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Info partita
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF8F9FA),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE0E0E0)),
              ),
              child: Column(
                children: [
                  Text(
                    '${widget.match.homeTeam} vs ${widget.match.awayTeam}',
                    style: const TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (widget.match.category != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      widget.match.category!,
                      style: const TextStyle(
                        fontSize: 12,
                        color: Color(0xFF666666),
                      ),
                    ),
                  ],
                ],
              ),
            ),

            const SizedBox(height: 20),

            // Input punteggi
            Row(
              children: [
                // Squadra casa
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Text(
                        widget.match.homeTeam,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isAuroraHome ? FontWeight.bold : FontWeight.w600,
                          color: isAuroraHome ? const Color(0xFF1976D2) : const Color(0xFF333333),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 60,
                        child: TextFormField(
                          controller: _homeScoreController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isAuroraHome ? const Color(0xFF1976D2) : const Color(0xFFE0E0E0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1976D2),
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Richiesto';
                            }
                            final score = int.tryParse(value);
                            if (score == null || score < 0 || score > 20) {
                              return 'Tra 0-20';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),

                // Separatore VS
                const Expanded(
                  flex: 1,
                  child: Text(
                    '-',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF666666),
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),

                // Squadra ospite
                Expanded(
                  flex: 3,
                  child: Column(
                    children: [
                      Text(
                        widget.match.awayTeam,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isAuroraAway ? FontWeight.bold : FontWeight.w600,
                          color: isAuroraAway ? const Color(0xFF1976D2) : const Color(0xFF333333),
                        ),
                        textAlign: TextAlign.center,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 8),
                      Container(
                        width: 60,
                        child: TextFormField(
                          controller: _awayScoreController,
                          textAlign: TextAlign.center,
                          keyboardType: TextInputType.number,
                          inputFormatters: [
                            FilteringTextInputFormatter.digitsOnly,
                            LengthLimitingTextInputFormatter(2),
                          ],
                          decoration: InputDecoration(
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: BorderSide(
                                color: isAuroraAway ? const Color(0xFF1976D2) : const Color(0xFFE0E0E0),
                              ),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(
                                color: Color(0xFF1976D2),
                                width: 2,
                              ),
                            ),
                          ),
                          validator: (value) {
                            if (value == null || value.isEmpty) {
                              return 'Richiesto';
                            }
                            final score = int.tryParse(value);
                            if (score == null || score < 0 || score > 20) {
                              return 'Tra 0-20';
                            }
                            return null;
                          },
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Info aggiuntiva
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0xFFF0F7FF),
                borderRadius: BorderRadius.circular(6),
                border: Border.all(color: const Color(0xFFB3D9FF)),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    size: 16,
                    color: Color(0xFF1976D2),
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Il risultato verrà salvato localmente e sincronizzato con il database se disponibile.',
                      style: TextStyle(
                        fontSize: 11,
                        color: Color(0xFF1976D2),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text(
            'Annulla',
            style: TextStyle(color: Colors.grey),
          ),
        ),
        ElevatedButton(
          onPressed: () {
            if (_formKey.currentState!.validate()) {
              final homeScore = int.parse(_homeScoreController.text);
              final awayScore = int.parse(_awayScoreController.text);
              Navigator.of(context).pop({
                'homeScore': homeScore,
                'awayScore': awayScore,
              });
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
          ),
          child: const Text('Salva'),
        ),
      ],
    );
  }
}