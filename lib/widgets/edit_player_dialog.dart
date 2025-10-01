import 'package:flutter/material.dart';
import '../models/player_model.dart';

class EditPlayerDialog extends StatefulWidget {
  final Player player;
  final Function(Player) onSave;

  const EditPlayerDialog({
    super.key,
    required this.player,
    required this.onSave,
  });

  @override
  State<EditPlayerDialog> createState() => _EditPlayerDialogState();
}

class _EditPlayerDialogState extends State<EditPlayerDialog> {
  final _formKey = GlobalKey<FormState>();
  late TextEditingController _nameController;
  String? _selectedPosition; // New variable to hold selected position
  late TextEditingController _jerseyController;

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
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.player.name);
    // Ensure the initial position is one of the valid roles, otherwise set to null
    if (widget.player.position != null && _playerRoles.contains(widget.player.position)) {
      _selectedPosition = widget.player.position;
    } else {
      _selectedPosition = null; // Or set a default valid role if desired
    }
    _jerseyController = TextEditingController(text: widget.player.jerseyNumber?.toString());
  }

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
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
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
                    style: TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                  const SizedBox(height: 4),
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
                        child: Text(role),
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
          child: const Text('Salva'),
        ),
      ],
    );
  }

  void _savePlayer() {
    if (_formKey.currentState!.validate()) {
      final updatedPlayer = widget.player.copyWith(
        name: _nameController.text.trim(),
        position: _selectedPosition,
        jerseyNumber: _jerseyController.text.trim().isEmpty ? null : int.tryParse(_jerseyController.text.trim()),
      );

      widget.onSave(updatedPlayer);
    }
  }
}