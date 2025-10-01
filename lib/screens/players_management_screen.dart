import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/player_service.dart';
import '../widgets/add_player_dialog.dart';

class PlayersManagementScreen extends StatefulWidget {
  const PlayersManagementScreen({super.key});

  @override
  State<PlayersManagementScreen> createState() => _PlayersManagementScreenState();
}

class _PlayersManagementScreenState extends State<PlayersManagementScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final playerService = context.read<PlayerService>();
      playerService.loadPlayers();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const Text(
            'Gestione Giocatori',
            style: TextStyle(
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          backgroundColor: const Color(0xFF1E3A8A),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: SafeArea(
          child: Consumer<PlayerService>(
          builder: (context, playerService, child) {
            if (playerService.isLoading && playerService.players.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            if (playerService.players.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.person_outline,
                      size: 64,
                      color: Colors.grey[400],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'Nessun giocatore registrato',
                      style: TextStyle(
                        fontSize: 18,
                        color: Colors.grey[600],
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Tocca + per aggiungere il primo giocatore',
                      style: TextStyle(fontSize: 14, color: Colors.grey),
                    ),
                  ],
                ),
              );
            }

            return Column(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  color: Colors.white,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'Giocatori (${playerService.players.length})',
                        style: const TextStyle(
                          fontSize: 8,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: () => _showAddPlayerDialog(),
                        icon: const Icon(Icons.add, size: 18),
                        label: const Text('Aggiungi'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1E3A8A),
                          foregroundColor: Colors.white,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.separated(
                    padding: const EdgeInsets.all(16),
                    itemCount: playerService.players.length,
                    separatorBuilder: (context, index) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final player = playerService.players[index];
                      return Card(
                        elevation: 2,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                          leading: CircleAvatar(
                            radius: 18,
                            backgroundColor: const Color(0xFF1E3A8A),
                            child: Text(
                              player.jerseyNumber?.toString() ?? '#',
                              style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 10,
                              ),
                            ),
                          ),
                          title: Text(
                            player.name,
                            style: const TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 10,
                            ),
                          ),
                          subtitle: player.position != null 
                              ? Text(
                                  'Ruolo: ${player.position}',
                                  style: TextStyle(
                                    color: Colors.grey[600],
                                    fontSize: 10,
                                  ),
                                )
                              : null,
                          trailing: PopupMenuButton(
                            icon: const Icon(Icons.more_vert),
                            itemBuilder: (context) => [
                              const PopupMenuItem(
                                value: 'edit',
                                child: Row(
                                  children: [
                                    Icon(Icons.edit, size: 20),
                                    SizedBox(width: 8),
                                    Text('Modifica'),
                                  ],
                                ),
                              ),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Row(
                                  children: [
                                    Icon(Icons.delete, size: 20, color: Colors.red),
                                    SizedBox(width: 8),
                                    Text('Elimina', style: TextStyle(color: Colors.red)),
                                  ],
                                ),
                              ),
                            ],
                            onSelected: (value) async {
                              if (value == 'delete') {
                                _showDeleteConfirmDialog(player.id!, player.name);
                              } else if (value == 'edit') {
                                _showEditPlayerDialog(player);
                              }
                            },
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ],
            );
          },
          ),
        ),
      );
  }

  void _showAddPlayerDialog() {
    showDialog(
      context: context,
      builder: (context) => AddPlayerDialog(
        onSave: (player) async {
          final playerService = context.read<PlayerService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          
          final success = await playerService.addPlayer(player);
          
          if (success) {
            navigator.pop();
            messenger.showSnackBar(
              const SnackBar(content: Text('Giocatore aggiunto con successo!')),
            );
          } else {
            navigator.pop();
            messenger.showSnackBar(
              SnackBar(
                content: Text(playerService.errorMessage ?? 'Errore nell\'aggiunta del giocatore'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditPlayerDialog(player) {
    // For now, just show a message that editing is not implemented
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Funzionalità di modifica in sviluppo')),
    );
  }

  void _showDeleteConfirmDialog(String playerId, String playerName) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Conferma Eliminazione'),
          content: Text('Sei sicuro di voler eliminare "$playerName"?'),
          actions: [
            TextButton(
              child: const Text('Annulla'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Elimina', style: TextStyle(color: Colors.red)),
              onPressed: () {
                Navigator.of(context).pop();
                context.read<PlayerService>().deletePlayer(playerId);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Giocatore eliminato')),
                );
              },
            ),
          ],
        );
      },
    );
  }
}