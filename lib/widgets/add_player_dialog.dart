import 'package:flutter/material.dart';
import '../models/player_model.dart';

class AddPlayerDialog extends StatefulWidget {
  final Function(Player) onSave;
  final String? teamCategory;

  const AddPlayerDialog({super.key, required this.onSave, this.teamCategory});

  @override
  State<AddPlayerDialog> createState() => _AddPlayerDialogState();
}

class _AddPlayerDialogState extends State<AddPlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedPosition; // New variable to hold selected position
  final _jerseyController = TextEditingController();

  final List<String> _playerRoles = [
    'Portiere',
    'Difensore Centrale',
    'Terzino Dx',
    'Terzino Sx',
    'Centrocampista',
    'Esterno Dx',
    'Esterno Sx',
    'Attaccante',
    'Mediano',
    'Trequartista',
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _jerseyController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      content: SizedBox(
        width: MediaQuery.of(context).size.width * 0.9,
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Nome e Cognome *',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 3),
                  TextFormField(
                    controller: _nameController,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.person),
                      border: OutlineInputBorder(),
                    ),
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Inserisci il nome del giocatore';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Ruolo (opzionale)',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 3),
                  DropdownButtonFormField<String>(
                    isExpanded: true,
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.sports_soccer),
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedPosition,
                    items: _playerRoles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(
                          role,
                          overflow: TextOverflow.ellipsis,
                        ),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedPosition = value;
                      });
                    },
                    validator: (value) {
                      // Optional: Add validation if role is mandatory
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _jerseyController,
                decoration: const InputDecoration(
                  labelText: 'nr. maglia',
                  prefixIcon: Icon(Icons.confirmation_number),
                  border: OutlineInputBorder(),
                ),
                keyboardType: TextInputType.number,
                validator: (value) {
                  if (value != null && value.isNotEmpty) {
                    final number = int.tryParse(value);
                    if (number == null || number < 1 || number > 99) {
                      return 'Inserisci un numero valido (1-99)';
                    }
                  }
                  return null;
                },
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Annulla'),
        ),
        ElevatedButton(
          onPressed: _savePlayer,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF1E3A8A),
            foregroundColor: Colors.white,
          ),
          child: const Text('Aggiungi'),
        ),
      ],
    );
  }

  void _savePlayer() {
    if (_formKey.currentState!.validate()) {
      debugPrint('=== SAVING PLAYER ===');
      debugPrint('Name: ${_nameController.text.trim()}');
      debugPrint('Position: $_selectedPosition');
      debugPrint('Jersey: ${_jerseyController.text.trim()}');
      debugPrint('Team Category: ${widget.teamCategory}');
      
      final player = Player(
        name: _nameController.text.trim(),
        position: _selectedPosition,
        jerseyNumber: _jerseyController.text.trim().isEmpty ? null : int.tryParse(_jerseyController.text.trim()),
        teamCategory: widget.teamCategory,
        isStaff: false,
      );
      
      debugPrint('Player created: ${player.toJson()}');
      widget.onSave(player);
    }
  }
}