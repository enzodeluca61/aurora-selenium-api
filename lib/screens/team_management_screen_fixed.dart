import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../services/team_service.dart';
import '../services/player_service.dart';
import '../widgets/add_player_dialog.dart';
import '../widgets/add_staff_dialog.dart';

class TeamManagementScreen extends StatefulWidget {
  const TeamManagementScreen({super.key});

  @override
  State<TeamManagementScreen> createState() => _TeamManagementScreenState();
}

class _TeamManagementScreenState extends State<TeamManagementScreen> {
  Team? selectedTeam;
  String activeTab = 'players'; // 'players' or 'staff'
  bool isDesktopLayout = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final teamService = context.read<TeamService>();
      final playerService = context.read<PlayerService>();
      
      if (teamService.teams.isEmpty && !teamService.isLoading) {
        teamService.loadTeams();
      }
      if (playerService.players.isEmpty && !playerService.isLoading) {
        playerService.loadPlayers();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        title: const Text(
          'Gestione Squadre',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        backgroundColor: const Color(0xFF4CAF50),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Team selector per mobile
          if (!isDesktopLayout && selectedTeam != null)
            IconButton(
              icon: const Icon(Icons.swap_horiz),
              onPressed: () => _showTeamSelector(),
            ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          isDesktopLayout = constraints.maxWidth > 800;
          
          return Consumer2<TeamService, PlayerService>(
            builder: (context, teamService, playerService, child) {
              if (teamService.isLoading && teamService.teams.isEmpty) {
                return const Center(child: CircularProgressIndicator());
              }

              if (teamService.teams.isEmpty) {
                return _buildNoTeamsView();
              }

              if (isDesktopLayout) {
                return _buildDesktopLayout(teamService, playerService, constraints);
              } else {
                return _buildMobileLayout(teamService, playerService, constraints);
              }
            },
          );
        },
      ),
    );
  }

  Widget _buildDesktopLayout(TeamService teamService, PlayerService playerService, BoxConstraints constraints) {
    return Row(
      children: [
        // Team selection sidebar
        Container(
          width: 250,
          color: Colors.white,
          child: _buildTeamSidebar(teamService.teams),
        ),
        // Main content area
        Expanded(
          child: selectedTeam == null
              ? _buildSelectTeamView()
              : _buildTeamDetailsView(playerService, constraints),
        ),
      ],
    );
  }

  Widget _buildMobileLayout(TeamService teamService, PlayerService playerService, BoxConstraints constraints) {
    if (selectedTeam == null) {
      return _buildMobileTeamSelector(teamService.teams);
    }
    return _buildTeamDetailsView(playerService, constraints);
  }

  Widget _buildMobileTeamSelector(List<Team> teams) {
    return Container(
      color: Colors.white,
      child: Column(
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
              border: Border(
                bottom: BorderSide(color: Colors.grey[300]!),
              ),
            ),
            child: const Text(
              'Seleziona Squadra',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Color(0xFF4CAF50),
              ),
            ),
          ),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.all(16),
              itemCount: teams.length,
              itemBuilder: (context, index) {
                final team = teams[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    title: Text(
                      team.category,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    leading: CircleAvatar(
                      backgroundColor: const Color(0xFF4CAF50),
                      child: const Icon(
                        Icons.sports_soccer,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    trailing: const Icon(Icons.arrow_forward_ios),
                    onTap: () {
                      setState(() {
                        selectedTeam = team;
                      });
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildNoTeamsView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.groups_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Nessuna squadra trovata',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Vai alle Impostazioni per aggiungere squadre',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamSidebar(List<Team> teams) {
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
            border: Border(
              bottom: BorderSide(color: Colors.grey[300]!),
            ),
          ),
          child: const Text(
            'Seleziona Squadra',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Color(0xFF4CAF50),
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: teams.length,
            itemBuilder: (context, index) {
              final team = teams[index];
              final isSelected = selectedTeam?.id == team.id;
              
              return Container(
                margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  color: isSelected ? const Color(0xFF4CAF50).withValues(alpha: 0.2) : null,
                ),
                child: ListTile(
                  title: Text(
                    team.category,
                    style: TextStyle(
                      fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                      color: isSelected ? const Color(0xFF4CAF50) : null,
                    ),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: isSelected ? const Color(0xFF4CAF50) : Colors.grey[300],
                    child: Icon(
                      Icons.sports_soccer,
                      color: isSelected ? Colors.white : Colors.grey[600],
                      size: 20,
                    ),
                  ),
                  onTap: () {
                    setState(() {
                      selectedTeam = team;
                    });
                  },
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildSelectTeamView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.arrow_back,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Seleziona una squadra',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Scegli una squadra dalla lista a sinistra per gestire giocatori e staff',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTeamDetailsView(PlayerService playerService, BoxConstraints constraints) {
    return Column(
      children: [
        // Header with team name and tabs
        Container(
          color: Colors.white,
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF4CAF50).withValues(alpha: 0.1),
                      const Color(0xFF4CAF50).withValues(alpha: 0.05),
                    ],
                  ),
                ),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(
                        Icons.sports_soccer,
                        color: Colors.white,
                        size: 24,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            selectedTeam!.category,
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF4CAF50),
                            ),
                          ),
                          Text(
                            'Gestione rosa e staff tecnico',
                            style: TextStyle(
                              fontSize: 12,
                              color: Colors.grey[600],
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (!isDesktopLayout)
                      IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => setState(() => selectedTeam = null),
                      ),
                  ],
                ),
              ),
              // Tabs
              Container(
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(color: Colors.grey[300]!),
                  ),
                ),
                child: Row(
                  children: [
                    _buildTab('players', 'Giocatori', Icons.person),
                    _buildTab('staff', 'Staff', Icons.person_pin),
                  ],
                ),
              ),
            ],
          ),
        ),
        // Content area
        Expanded(
          child: Container(
            color: const Color(0xFFF5F5F5),
            child: activeTab == 'players'
                ? _buildPlayersTab(playerService, constraints)
                : _buildStaffTab(playerService, constraints),
          ),
        ),
      ],
    );
  }

  Widget _buildTab(String tabId, String title, IconData icon) {
    final isActive = activeTab == tabId;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => activeTab = tabId),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            border: Border(
              bottom: BorderSide(
                color: isActive ? const Color(0xFF4CAF50) : Colors.transparent,
                width: 3,
              ),
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                color: isActive ? const Color(0xFF4CAF50) : Colors.grey[600],
                size: 18,
              ),
              const SizedBox(width: 6),
              Flexible(
                child: Text(
                  title,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: isActive ? const Color(0xFF4CAF50) : Colors.grey[600],
                    fontWeight: isActive ? FontWeight.bold : FontWeight.normal,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayersTab(PlayerService playerService, BoxConstraints constraints) {
    final teamPlayers = playerService.getPlayersByTeam(selectedTeam!.category);
    
    return Column(
      children: [
        // Action bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      'Giocatori (${teamPlayers.length})',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF4CAF50),
                      ),
                    ),
                  ),
                  SizedBox(
                    width: constraints.maxWidth > 600 ? null : double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () => _showAddPlayerDialog(),
                      icon: const Icon(Icons.add, size: 18),
                      label: Text(constraints.maxWidth > 400 ? 'Aggiungi Giocatore' : 'Aggiungi'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF4CAF50),
                        foregroundColor: Colors.white,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        // Players grid
        Expanded(
          child: teamPlayers.isEmpty
              ? _buildEmptyPlayersView()
              : _buildResponsivePlayersGrid(teamPlayers, constraints),
        ),
      ],
    );
  }

  Widget _buildResponsivePlayersGrid(List<Player> players, BoxConstraints constraints) {
    // Calcola il numero di colonne in base alla larghezza
    int crossAxisCount;
    if (constraints.maxWidth > 1200) {
      crossAxisCount = 4;
    } else if (constraints.maxWidth > 800) {
      crossAxisCount = 3;
    } else if (constraints.maxWidth > 500) {
      crossAxisCount = 2;
    } else {
      crossAxisCount = 1;
    }

    return GridView.builder(
      padding: const EdgeInsets.all(16),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: crossAxisCount,
        crossAxisSpacing: 12,
        mainAxisSpacing: 12,
        childAspectRatio: crossAxisCount == 1 ? 3.0 : 0.8,
      ),
      itemCount: players.length,
      itemBuilder: (context, index) {
        final player = players[index];
        return crossAxisCount == 1 
            ? _buildPlayerListTile(player)
            : _buildPlayerCard(player);
      },
    );
  }

  Widget _buildPlayerListTile(Player player) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(12),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF4CAF50),
          child: Text(
            player.jerseyNumber?.toString() ?? '#',
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
        ),
        title: Text(
          player.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: player.position != null
            ? Text(player.position!)
            : null,
        trailing: PopupMenuButton(
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
          onSelected: (value) => _handlePlayerAction(value, player),
        ),
        onTap: () => _showPlayerDetails(player),
      ),
    );
  }

  Widget _buildStaffTab(PlayerService playerService, BoxConstraints constraints) {
    final teamStaff = playerService.getStaffByTeam(selectedTeam!.category);
    
    return Column(
      children: [
        // Action bar
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.white,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'Staff Tecnico (${teamStaff.length})',
                  style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF4CAF50),
                  ),
                ),
              ),
              SizedBox(
                width: constraints.maxWidth > 600 ? null : double.infinity,
                child: ElevatedButton.icon(
                  onPressed: () => _showAddStaffDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: Text(constraints.maxWidth > 400 ? 'Aggiungi Staff' : 'Aggiungi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                ),
              ),
            ],
          ),
        ),
        // Staff list
        Expanded(
          child: teamStaff.isEmpty
              ? _buildEmptyStaffView()
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: teamStaff.length,
                  itemBuilder: (context, index) {
                    final staff = teamStaff[index];
                    return _buildStaffCard(staff);
                  },
                ),
        ),
      ],
    );
  }

  void _showTeamSelector() {
    final teamService = context.read<TeamService>();
    
    showModalBottomSheet(
      context: context,
      builder: (context) => Container(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Seleziona Squadra',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            ...teamService.teams.map((team) => ListTile(
              title: Text(team.category),
              leading: CircleAvatar(
                backgroundColor: selectedTeam?.id == team.id 
                    ? const Color(0xFF4CAF50) 
                    : Colors.grey[300],
                child: Icon(
                  Icons.sports_soccer,
                  color: selectedTeam?.id == team.id 
                      ? Colors.white 
                      : Colors.grey[600],
                ),
              ),
              trailing: selectedTeam?.id == team.id 
                  ? const Icon(Icons.check, color: Color(0xFF4CAF50))
                  : null,
              onTap: () {
                setState(() {
                  selectedTeam = team;
                });
                Navigator.pop(context);
              },
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyPlayersView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_add_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun giocatore nella squadra',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tocca "Aggiungi Giocatore" per iniziare',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyStaffView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.person_pin_outlined,
              size: 64,
              color: Colors.grey[400],
            ),
            const SizedBox(height: 16),
            Text(
              'Nessun membro dello staff',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 18,
                color: Colors.grey[600],
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tocca "Aggiungi Staff" per iniziare',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPlayerCard(Player player) {
    return Card(
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showPlayerDetails(player),
        child: Column(
          children: [
            Expanded(
              flex: 2,
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  gradient: LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      const Color(0xFF4CAF50).withValues(alpha: 0.8),
                      const Color(0xFF4CAF50).withValues(alpha: 0.6),
                    ],
                  ),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircleAvatar(
                      radius: 25,
                      backgroundColor: Colors.white.withValues(alpha: 0.9),
                      child: Text(
                        player.jerseyNumber?.toString() ?? '#',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF4CAF50),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      player.name,
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 11,
                      ),
                    ),
                    if (player.position != null)
                      Text(
                        player.position!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9,
                          color: Colors.grey[600],
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStaffCard(Player staff) {
    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(6),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(6),
        leading: CircleAvatar(
          backgroundColor: const Color(0xFF4CAF50),
          child: Icon(
            staff.position?.toLowerCase().contains('allenatore') == true
                ? Icons.sports
                : Icons.person_pin,
            color: Colors.white,
          ),
        ),
        title: Text(
          staff.name,
          style: const TextStyle(
            fontWeight: FontWeight.bold,
          ),
        ),
        subtitle: staff.position != null
            ? Text(staff.position!)
            : null,
        trailing: PopupMenuButton(
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
          onSelected: (value) => _handleStaffAction(value, staff),
        ),
        onTap: () => _showStaffDetails(staff),
      ),
    );
  }

  void _showAddPlayerDialog() {
    showDialog(
      context: context,
      builder: (context) => AddPlayerDialog(
        teamCategory: selectedTeam!.category,
        onSave: (player) async {
          final playerService = context.read<PlayerService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await playerService.addPlayer(player);
          
          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Giocatore aggiunto con successo!')), 
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(playerService.errorMessage ?? 'Errore nell\'aggiunta'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showAddStaffDialog() {
    showDialog(
      context: context,
      builder: (context) => AddStaffDialog(
        teamCategory: selectedTeam!.category,
        onSave: (staff) async {
          final playerService = context.read<PlayerService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await playerService.addStaff(staff);
          
          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Staff aggiunto con successo!')), 
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(playerService.errorMessage ?? 'Errore nell\'aggiunta'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showPlayerDetails(Player player) {
    // TODO: Implement player details dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dettagli di ${player.name} - In sviluppo')),
    );
  }

  void _showStaffDetails(Player staff) {
    // TODO: Implement staff details dialog
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Dettagli di ${staff.name} - In sviluppo')),
    );
  }

  void _handlePlayerAction(String action, Player player) {
    if (action == 'delete') {
      _showDeletePlayerDialog(player);
    } else if (action == 'edit') {
      // TODO: Implement edit player dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifica giocatore - In sviluppo')),
      );
    }
  }

  void _handleStaffAction(String action, Player staff) {
    if (action == 'delete') {
      _showDeleteStaffDialog(staff);
    } else if (action == 'edit') {
      // TODO: Implement edit staff dialog
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Modifica staff - In sviluppo')),
      );
    }
  }

  void _showDeletePlayerDialog(Player player) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Conferma Eliminazione'),
          content: Text('Sei sicuro di voler eliminare "${player.name}" dalla squadra?'),
          actions: [
            TextButton(
              child: const Text('Annulla'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Elimina', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                final playerService = context.read<PlayerService>();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final success = await playerService.deletePlayer(player.id!);
                
                navigator.pop();
                if (success) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Giocatore eliminato con successo')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(playerService.errorMessage ?? 'Errore nell\'eliminazione'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showDeleteStaffDialog(Player staff) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Conferma Eliminazione'),
          content: Text('Sei sicuro di voler eliminare "${staff.name}" dallo staff?'),
          actions: [
            TextButton(
              child: const Text('Annulla'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Elimina', style: TextStyle(color: Colors.red)),
              onPressed: () async {
                final playerService = context.read<PlayerService>();
                final navigator = Navigator.of(context);
                final messenger = ScaffoldMessenger.of(context);
                final success = await playerService.deleteStaff(staff.id!);
                
                navigator.pop();
                if (success) {
                  messenger.showSnackBar(
                    const SnackBar(content: Text('Staff eliminato con successo')),
                  );
                } else {
                  messenger.showSnackBar(
                    SnackBar(
                      content: Text(playerService.errorMessage ?? 'Errore nell\'eliminazione'),
                      backgroundColor: Colors.red,
                    ),
                  );
                }
              },
            ),
          ],
        );
      },
    );
  }
}