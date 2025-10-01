import 'package:flutter/material.dart';
import '../models/player_model.dart';

class AddStaffDialog extends StatefulWidget {
  final Function(Player) onSave;
  final String? teamCategory;

  const AddStaffDialog({super.key, required this.onSave, this.teamCategory});

  @override
  State<AddStaffDialog> createState() => _AddStaffDialogState();
}

class _AddStaffDialogState extends State<AddStaffDialog> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  String? _selectedRole;

  final List<String> _staffRoles = [
    'Allenatore',
    'Vice Allenatore',
    'Preparatore Atletico',
    'Preparatore dei Portieri',
    'Team Manager',
    'Fisioterapista',
    'Medico Sociale',
    'Dirigente',
    'Accompagnatore',
    'Altro',
  ];

  @override
  void dispose() {
    _nameController.dispose();
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
                        return 'Inserisci il nome dello staff';
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
                    'Ruolo *',
                    style: TextStyle(fontSize: 10, color: Colors.grey),
                  ),
                  const SizedBox(height: 3),
                  DropdownButtonFormField<String>(
                    isExpanded: true, // Added this line
                    decoration: const InputDecoration(
                      prefixIcon: Icon(Icons.work),
                      border: OutlineInputBorder(),
                    ),
                    value: _selectedRole,
                    items: _staffRoles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      );
                    }).toList(),
                    onChanged: (value) {
                      setState(() {
                        _selectedRole = value;
                      });
                    },
                    validator: (value) {
                      if (value == null || value.isEmpty) {
                        return 'Seleziona un ruolo';
                      }
                      return null;
                    },
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFF4CAF50).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      color: const Color(0xFF4CAF50),
                      size: 20,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.teamCategory != null 
                            ? 'Staff per: ${widget.teamCategory}'
                            : 'Staff generale',
                        style: TextStyle(
                          color: const Color(0xFF4CAF50),
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
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
          onPressed: _saveStaff,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF4CAF50),
            foregroundColor: Colors.white,
          ),
          child: const Text('Aggiungi'),
        ),
      ],
    );
  }

  void _saveStaff() {
    if (_formKey.currentState!.validate()) {
      final staff = Player(
        name: _nameController.text.trim(),
        position: _selectedRole,
        teamCategory: widget.teamCategory,
        isStaff: true,
      );
      
      widget.onSave(staff);
    }
  }
}