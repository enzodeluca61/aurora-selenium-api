import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:flutter/services.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf;
import '../models/team_model.dart';
import '../models/player_model.dart';
import '../services/team_service.dart';
import '../services/player_service.dart';
import '../widgets/add_player_dialog.dart';
import '../widgets/add_staff_dialog.dart';
import '../widgets/edit_player_dialog.dart';
import '../widgets/edit_staff_dialog.dart';

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
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Gestione Squadre',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 16,
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
      body: SafeArea(
        child: LayoutBuilder(
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
                  ElevatedButton.icon(
                    onPressed: () => _showAddPlayerDialog(),
                    icon: const Icon(Icons.add, size: 18),
                    label: const Text(''),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF4CAF50),
                      foregroundColor: Colors.white,
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
        crossAxisSpacing: 2,
        mainAxisSpacing: 1,
        childAspectRatio: crossAxisCount == 1 ? 4.8 : 0.8,
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
        contentPadding: const EdgeInsets.all(2),
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
          player.name.toUpperCase(), // To uppercase
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 14, // Reduced font size
          ),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            // Numero maglia rimosso - solo pallino visibile
            if (player.position != null)
              Text(player.position!),
          ],
        ),
        trailing: player.name != '--- VUOTO ---' ? PopupMenuButton(
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
        ) : null,
        onTap: player.name != '--- VUOTO ---' ? () => _showPlayerDetails(player) : null,
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
              ElevatedButton.icon(
                  onPressed: () => _showAddStaffDialog(),
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text(''),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
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

  // Funzione per generare PDF con i dati dei giocatori usando modello
  Future<void> _generatePlayersPDF() async {
    if (selectedTeam == null) return;
    
    try {
      // Carica il modello PDF
      final pdfTemplate = await rootBundle.load('assets/pdf/modello_giocatori.pdf');
      final templateBytes = pdfTemplate.buffer.asUint8List();
      
      // Crea dati di fantasia per il test (primi 12 giocatori)
      final testPlayers = _generateTestPlayers(12);
      
      // Carica il documento PDF esistente usando Syncfusion
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: templateBytes);
      
      // Ottieni la prima pagina
      final sf.PdfPage page = document.pages[0];
      
      // Ottieni la grafica della pagina per disegnare il testo
      final sf.PdfGraphics graphics = page.graphics;
      
      // Configura il font (ridotto di 1 punto)
      final sf.PdfFont font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11);
      final sf.PdfFont boldFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11, style: sf.PdfFontStyle.bold);
      
      // Posizioni per le colonne (coordinate PDF: origine in basso a sinistra)
      const double pageHeight = 842; // Altezza pagina A4 in punti (29.7cm)
      
      // Sistema coordinate PDF: origine (0,0) in BASSO A SINISTRA
      // Per posizionare a 62mm dall'ALTO devo calcolare dal BASSO
      // Altezza A4 = 297mm, quindi 62mm dall'alto = 297-62 = 235mm dal basso
      const double startY = (297 - 62) * 2.834645; // 235mm dal basso = 666.1 punti
      const double rowHeight = 7 * 2.834645; // 7mm tra le righe = 19.8 punti
      
      // Posizioni X delle colonne (centro del testo, convertite da mm)
      const double giornoX = 21 * 2.834645;    // 21mm = 59.5 punti - Colonna G
      const double meseX = 29 * 2.834645;      // 29mm = 82.2 punti - Colonna M  
      const double annoX = 37 * 2.834645;      // 37mm = 104.9 punti - Colonna A
      const double cognomeNomeStartX = 43 * 2.834645; // 43mm = 121.9 punti - Inizio Cognome e Nome
      const double cognomeX = cognomeNomeStartX;  // Cognome inizia a 43mm
      const double nomeX = cognomeNomeStartX + 100; // Nome spostato a destra del cognome
      
      // RIGA GRADUATA VERTICALE per capire le coordinate
      // Disegna linea verticale da (0,0) verso l'alto
      graphics.drawLine(
        sf.PdfPen(sf.PdfColor(255, 0, 0), width: 1), // Linea rossa
        Offset(0, 0), // Punto di partenza (origine)
        Offset(0, pageHeight), // Punto finale (in cima alla pagina)
      );
      
      // Disegna tacche graduate ogni 10mm con numeri
      final sf.PdfFont smallFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 14);
      
      for (int mm = 0; mm <= 297; mm += 10) { // Ogni 10mm fino a 297mm (altezza A4)
        final double yPos = mm * 2.834645; // Converti mm in punti
        
        // Tacca più lunga ogni 50mm, più corta ogni 10mm
        final double tickLength = (mm % 50 == 0) ? 20 : 10;
        
        // Disegna la tacca orizzontale
        graphics.drawLine(
          sf.PdfPen(sf.PdfColor(255, 0, 0), width: 1),
          Offset(0, yPos),
          Offset(tickLength, yPos),
        );
        
        // Scrivi il numero ogni 50mm
        if (mm % 50 == 0) {
          graphics.drawString(
            '${mm}mm',
            smallFont,
            bounds: Rect.fromLTWH(25, yPos - 5, 50, 15),
            brush: sf.PdfSolidBrush(sf.PdfColor(255, 0, 0)),
          );
        }
      }
      
      // Disegna anche un punto nell'angolo per vedere l'origine
      graphics.drawRectangle(
        pen: sf.PdfPen(sf.PdfColor(0, 255, 0), width: 5), // Punto verde
        bounds: Rect.fromLTWH(0, 0, 10, 10), // Origine (0,0)
      );
      
      // TEST: Scrivi a 59mm dal basso usando le coordinate corrette
      final double testY = 59 * 2.834645; // 59mm = 167.2 punti dal basso
      
      // Posizioni definitive corrette (sovrascrivono quelle precedenti)
      final double finalGiornoX = 19 * 2.834645;    // G: 19mm (corretto)
      final double finalMeseX = 26 * 2.834645;      // M: 26mm (spostato 1mm a sinistra)
      final double finalAnnoX = 32 * 2.834645;      // A: 32mm (spostato 1mm a sinistra)
      final double finalCognomeNomeX = 46 * 2.834645; // Cognome/Nome: 46mm (corretto)
      final double finalMatricolaX = 113 * 2.834645; // Matricola: 113mm dal bordo sinistro
      
      // Dati di prova per 12 righe (anno completo 2011 + matricola)
      final List<Map<String, String>> testData = [
        {'g': '01', 'm': '02', 'a': '2011', 'nome': 'ROSSI GIACOMO', 'matricola': '1234567890'},
        {'g': '15', 'm': '03', 'a': '2011', 'nome': 'BIANCHI MARCO', 'matricola': '1234567890'},
        {'g': '22', 'm': '07', 'a': '2011', 'nome': 'VERDI LUCA', 'matricola': '1234567890'},
        {'g': '08', 'm': '12', 'a': '2011', 'nome': 'FERRARI ANDREA', 'matricola': '1234567890'},
        {'g': '30', 'm': '01', 'a': '2011', 'nome': 'COLOMBO MATTEO', 'matricola': '1234567890'},
        {'g': '12', 'm': '09', 'a': '2011', 'nome': 'RICCI DAVIDE', 'matricola': '1234567890'},
        {'g': '25', 'm': '05', 'a': '2011', 'nome': 'MARINO ALESSANDRO', 'matricola': '1234567890'},
        {'g': '03', 'm': '11', 'a': '2011', 'nome': 'GRECO TOMMASO', 'matricola': '1234567890'},
        {'g': '18', 'm': '04', 'a': '2011', 'nome': 'BRUNO FRANCESCO', 'matricola': '1234567890'},
        {'g': '29', 'm': '08', 'a': '2011', 'nome': 'GALLO LORENZO', 'matricola': '1234567890'},
        {'g': '11', 'm': '10', 'a': '2011', 'nome': 'CONTI RICCARDO', 'matricola': '1234567890'},
        {'g': '07', 'm': '06', 'a': '2011', 'nome': 'VILLA GABRIELE', 'matricola': '1234567890'},
      ];
      
      // Disegna 12 righe con spaziatura di 7mm
      for (int i = 0; i < testData.length; i++) {
        final double currentY = testY + (i * 7 * 2.834645); // 7mm tra le righe
        final data = testData[i];
        
        // Giorno
        graphics.drawString(
          data['g']!,
          font,
          bounds: Rect.fromLTWH(finalGiornoX, currentY, 20, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 255)), // Blu per test
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // Mese
        graphics.drawString(
          data['m']!,
          font,
          bounds: Rect.fromLTWH(finalMeseX, currentY, 20, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 255)), // Blu per test
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // Anno
        graphics.drawString(
          data['a']!,
          font,
          bounds: Rect.fromLTWH(finalAnnoX, currentY, 40, 20), // Larghezza aumentata da 20 a 40
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 255)), // Blu per test
          format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
        );
        
        // Cognome Nome
        graphics.drawString(
          data['nome']!,
          boldFont,
          bounds: Rect.fromLTWH(finalCognomeNomeX, currentY, 200, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 255)), // Blu per test
        );
        
        // Matricola
        graphics.drawString(
          data['matricola']!,
          font,
          bounds: Rect.fromLTWH(finalMatricolaX, currentY, 80, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 255)), // Blu per test
        );
      }
      
      // Altri giocatori rimossi per il test
      /* for (int i = 0; i < testPlayers.length; i++) {
        final player = testPlayers[i];
        final currentY = pageHeight - startY - (i * rowHeight);
        
        // Numero rimosso come richiesto
        
        // Giorno
        graphics.drawString(
          player['giorno'],
          font,
          bounds: Rect.fromLTWH(giornoX, currentY, 30, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Mese
        graphics.drawString(
          player['mese'],
          font,
          bounds: Rect.fromLTWH(meseX, currentY, 30, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Anno
        graphics.drawString(
          player['anno'],
          font,
          bounds: Rect.fromLTWH(annoX, currentY, 30, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Cognome (maiuscolo e grassetto)
        graphics.drawString(
          player['cognome'].toUpperCase(),
          boldFont,
          bounds: Rect.fromLTWH(cognomeX, currentY, 120, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
        
        // Nome
        graphics.drawString(
          player['nome'],
          font,
          bounds: Rect.fromLTWH(nomeX, currentY, 120, 20),
          brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
        );
      } */
      
      // Salva il documento e mostra l'anteprima
      final List<int> bytes = await document.save();
      document.dispose();
      
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => Uint8List.fromList(bytes),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nel caricamento del modello PDF: $e')),
      );
    }
  }
  
  // Genera dati di fantasia per il test
  List<Map<String, dynamic>> _generateTestPlayers(int count) {
    final nomi = ['Mario', 'Luca', 'Andrea', 'Francesco', 'Alessandro', 'Matteo', 'Lorenzo', 'Davide', 'Riccardo', 'Tommaso', 'Gabriele', 'Simone'];
    final cognomi = ['Rossi', 'Verdi', 'Bianchi', 'Neri', 'Gialli', 'Ferrari', 'Colombo', 'Ricci', 'Marino', 'Greco', 'Bruno', 'Gallo'];
    
    return List.generate(count, (index) {
      final random = DateTime.now().millisecondsSinceEpoch + index;
      final anno = 2005 + (random % 10); // Anni tra 2005-2014
      final mese = 1 + (random % 12);
      final giorno = 1 + (random % 28);
      
      return {
        'numero': index + 1,
        'giorno': giorno.toString().padLeft(2, '0'),
        'mese': mese.toString().padLeft(2, '0'),
        'anno': (anno % 100).toString().padLeft(2, '0'),
        'cognome': cognomi[index % cognomi.length],
        'nome': nomi[index % nomi.length],
      };
    });
  }
  
  // Crea overlay con i dati dei giocatori posizionati sulle righe
  List<pw.Widget> _buildPlayerDataOverlay(List<Map<String, dynamic>> players) {
    List<pw.Widget> overlays = [];
    
    // Posizioni approssimative per un PDF A4 con tabella (da aggiustare in base al tuo modello)
    const double startY = 700; // Posizione Y della prima riga (dall'alto)
    const double rowHeight = 30; // Altezza di ogni riga
    
    // Posizioni X delle colonne
    const double numeroX = 50;    // Colonna numero
    const double giornoX = 120;   // Colonna giorno
    const double meseX = 160;     // Colonna mese  
    const double annoX = 200;     // Colonna anno
    const double cognomeX = 280;  // Colonna cognome
    const double nomeX = 400;     // Colonna nome
    
    for (int i = 0; i < players.length; i++) {
      final player = players[i];
      final currentY = startY - (i * rowHeight);
      
      // Numero
      overlays.add(
        pw.Positioned(
          left: numeroX,
          top: currentY,
          child: pw.Text(
            player['numero'].toString(),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
      
      // Giorno
      overlays.add(
        pw.Positioned(
          left: giornoX,
          top: currentY,
          child: pw.Text(
            player['giorno'],
            style: const pw.TextStyle(fontSize: 12),
          ),
        ),
      );
      
      // Mese
      overlays.add(
        pw.Positioned(
          left: meseX,
          top: currentY,
          child: pw.Text(
            player['mese'],
            style: const pw.TextStyle(fontSize: 12),
          ),
        ),
      );
      
      // Anno
      overlays.add(
        pw.Positioned(
          left: annoX,
          top: currentY,
          child: pw.Text(
            player['anno'],
            style: const pw.TextStyle(fontSize: 12),
          ),
        ),
      );
      
      // Cognome
      overlays.add(
        pw.Positioned(
          left: cognomeX,
          top: currentY,
          child: pw.Text(
            player['cognome'].toUpperCase(),
            style: pw.TextStyle(fontSize: 12, fontWeight: pw.FontWeight.bold),
          ),
        ),
      );
      
      // Nome
      overlays.add(
        pw.Positioned(
          left: nomeX,
          top: currentY,
          child: pw.Text(
            player['nome'],
            style: const pw.TextStyle(fontSize: 12),
          ),
        ),
      );
    }
    
    return overlays;
  }

  pw.Widget _buildPlayersPDFTable(List<Player> players) {
    return pw.Table(
      border: pw.TableBorder.all(color: PdfColors.grey600, width: 1),
      columnWidths: const {
        0: pw.FlexColumnWidth(1),
        1: pw.FlexColumnWidth(2),
        2: pw.FlexColumnWidth(2),
        3: pw.FlexColumnWidth(1.5),
      },
      children: [
        // Header
        pw.TableRow(
          decoration: pw.BoxDecoration(
            color: PdfColors.green600,
          ),
          children: [
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'N°',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'COGNOME',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'NOME',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 12,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
            pw.Container(
              padding: const pw.EdgeInsets.all(8),
              child: pw.Text(
                'DATA NASCITA\n(gg/mm/aa)',
                style: pw.TextStyle(
                  color: PdfColors.white,
                  fontWeight: pw.FontWeight.bold,
                  fontSize: 10,
                ),
                textAlign: pw.TextAlign.center,
              ),
            ),
          ],
        ),
        // Righe giocatori
        ...players.asMap().entries.map((entry) {
          final index = entry.key;
          final player = entry.value;
          final isEven = index % 2 == 0;
          
          return pw.TableRow(
            decoration: pw.BoxDecoration(
              color: isEven ? PdfColors.grey100 : PdfColors.white,
            ),
            children: [
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  player.jerseyNumber?.toString() ?? '${index + 1}',
                  style: const pw.TextStyle(fontSize: 11),
                  textAlign: pw.TextAlign.center,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  player.lastName.toUpperCase(),
                  style: pw.TextStyle(fontSize: 11, fontWeight: pw.FontWeight.bold),
                  textAlign: pw.TextAlign.left,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  player.firstName,
                  style: const pw.TextStyle(fontSize: 11),
                  textAlign: pw.TextAlign.left,
                ),
              ),
              pw.Container(
                padding: const pw.EdgeInsets.all(8),
                child: pw.Text(
                  player.birthDateFormatted,
                  style: const pw.TextStyle(fontSize: 11),
                  textAlign: pw.TextAlign.center,
                ),
              ),
            ],
          );
        }).toList(),
      ],
    );
  }

  // Dialog per le distinte tornei
  void _showTournamentDistinctionsDialog() {
    final teamService = context.read<TeamService>();
    String? selectedCategory = selectedTeam?.category;
    bool selectAll = false;
    bool selectEmpty = false;
    
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              title: Row(
                children: [
                  const Icon(Icons.emoji_events, color: Color(0xFF4CAF50)),
                  const SizedBox(width: 8),
                  const Text(
                    'Distinte Tornei',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Seleziona la categoria per generare la distinta:',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 16),
                  Container(
                    width: double.maxFinite,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade400),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: selectedCategory,
                        hint: const Text('Seleziona categoria'),
                        isExpanded: true,
                        items: teamService.teams.map((team) {
                          return DropdownMenuItem<String>(
                            value: team.category,
                            child: Text(
                              team.category,
                              style: const TextStyle(fontSize: 14),
                            ),
                          );
                        }).toList(),
                        onChanged: (String? newValue) {
                          setState(() {
                            selectedCategory = newValue;
                          });
                        },
                      ),
                    ),
                  ),
                  // Mostra i checkbox solo se è stata selezionata una categoria
                  if (selectedCategory != null) ...[
                    const SizedBox(height: 20),
                    const Text(
                      'Opzioni di selezione:',
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 12),
                    // Checkbox TUTTI
                    Row(
                      children: [
                        Checkbox(
                          value: selectAll,
                          onChanged: (bool? value) {
                            setState(() {
                              selectAll = value ?? false;
                            });
                          },
                          activeColor: const Color(0xFF4CAF50),
                        ),
                        const Text(
                          'TUTTI',
                          style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          selectedCategory!,
                          style: const TextStyle(fontSize: 14),
                        ),
                      ],
                    ),
                    // Checkbox VUOTO
                    Row(
                      children: [
                        Checkbox(
                          value: selectEmpty,
                          onChanged: (bool? value) {
                            setState(() {
                              selectEmpty = value ?? false;
                            });
                          },
                          activeColor: const Color(0xFF4CAF50),
                        ),
                        const CircleAvatar(
                          backgroundColor: Colors.grey,
                          radius: 10,
                          child: Text(
                            '0',
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Text(
                          '--- VUOTO ---',
                          style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Annulla'),
                ),
                ElevatedButton.icon(
                  onPressed: selectedCategory != null
                      ? () {
                          Navigator.of(context).pop();
                          _generateTournamentDistinction(selectedCategory!);
                        }
                      : null,
                  icon: const Icon(Icons.picture_as_pdf, size: 18),
                  label: const Text('Genera PDF'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4CAF50),
                    foregroundColor: Colors.white,
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  // Funzione per generare la distinta torneo
  Future<void> _generateTournamentDistinction(String category) async {
    try {
      // Carica il modello PDF
      final pdfTemplate = await rootBundle.load('assets/pdf/modello_giocatori.pdf');
      final templateBytes = pdfTemplate.buffer.asUint8List();
      
      // Ottieni i giocatori della categoria selezionata
      final playerService = context.read<PlayerService>();
      final players = playerService.players
          .where((player) => player.teamCategory == category && !player.isStaff)
          .toList();
      
      // Aggiungi un giocatore vuoto fittizio per permettere cella bianca
      final emptyPlayer = Player(
        name: '--- VUOTO ---',
        teamCategory: category,
        isStaff: false,
      );
      players.add(emptyPlayer);
      
      if (players.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Nessun giocatore trovato per la categoria $category')),
        );
        return;
      }
      
      // Carica il documento PDF esistente usando Syncfusion
      final sf.PdfDocument document = sf.PdfDocument(inputBytes: templateBytes);
      
      // Ottieni la prima pagina
      final sf.PdfPage page = document.pages[0];
      
      // Ottieni la grafica della pagina per disegnare il testo
      final sf.PdfGraphics graphics = page.graphics;
      
      // Configura il font (ridotto di 1 punto)
      final sf.PdfFont font = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11);
      final sf.PdfFont boldFont = sf.PdfStandardFont(sf.PdfFontFamily.helvetica, 11, style: sf.PdfFontStyle.bold);
      
      // Posizioni per le colonne (coordinate PDF: origine in basso a sinistra)
      const double pageHeight = 842; // Altezza pagina A4 in punti (29.7cm)
      
      // Sistema coordinate PDF: origine (0,0) in BASSO A SINISTRA
      // Per posizionare a 62mm dall'ALTO devo calcolare dal BASSO
      // Altezza A4 = 297mm, quindi 62mm dall'alto = 297-62 = 235mm dal basso
      const double startY = (297 - 62) * 2.834645; // 235mm dal basso = 666.1 punti
      const double rowHeight = 7 * 2.834645; // 7mm tra le righe = 19.8 punti
      
      // Posizioni X delle colonne (centro del testo, convertite da mm)
      const double giornoX = 21 * 2.834645;    // 21mm = 59.5 punti - Colonna G
      const double meseX = 29 * 2.834645;      // 29mm = 82.2 punti - Colonna M  
      const double annoX = 37 * 2.834645;      // 37mm = 104.9 punti - Colonna A
      const double cognomeNomeStartX = 43 * 2.834645; // 43mm = 121.9 punti - Inizio Cognome e Nome
      const double cognomeX = cognomeNomeStartX;  // Cognome inizia a 43mm
      const double nomeX = cognomeNomeStartX + 100; // Nome spostato a destra del cognome
      
      // Disegna i dati di ogni giocatore (massimo 20)
      final playersToShow = players.take(20).toList();
      
      for (int i = 0; i < playersToShow.length; i++) {
        final player = playersToShow[i];
        final currentY = startY - (i * rowHeight); // Sottrai per andare verso il basso (coordinate PDF)
        
        // Giorno
        if (player.birthDate != null) {
          graphics.drawString(
            player.birthDate!.day.toString().padLeft(2, '0'),
            font,
            bounds: Rect.fromLTWH(giornoX - 10, currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
            format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
          );
          
          // Mese
          graphics.drawString(
            player.birthDate!.month.toString().padLeft(2, '0'),
            font,
            bounds: Rect.fromLTWH(meseX - 10, currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
            format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
          );
          
          // Anno (ultime 2 cifre)
          graphics.drawString(
            (player.birthDate!.year % 100).toString().padLeft(2, '0'),
            font,
            bounds: Rect.fromLTWH(annoX - 10, currentY, 20, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
            format: sf.PdfStringFormat(alignment: sf.PdfTextAlignment.center),
          );
        }
        
        // Cognome (maiuscolo e grassetto) - solo se non è il giocatore vuoto
        if (player.name != '--- VUOTO ---') {
          graphics.drawString(
            player.lastName.toUpperCase(),
            boldFont,
            bounds: Rect.fromLTWH(cognomeX, currentY, 120, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
          
          // Nome
          graphics.drawString(
            player.firstName,
            font,
            bounds: Rect.fromLTWH(nomeX, currentY, 120, 20),
            brush: sf.PdfSolidBrush(sf.PdfColor(0, 0, 0)),
          );
        }
      }
      
      // Salva il documento e mostra l'anteprima
      final List<int> bytes = await document.save();
      document.dispose();
      
      await Printing.layoutPdf(
        onLayout: (PdfPageFormat format) async => Uint8List.fromList(bytes),
      );
      
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Errore nella generazione della distinta: $e')),
      );
    }
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
      child: SingleChildScrollView(
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
      ),
    );
  }

  Widget _buildEmptyStaffView() {
    return Center(
      child: SingleChildScrollView(
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
        onTap: player.name != '--- VUOTO ---' ? () => _showPlayerDetails(player) : null,
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
                      player.name.toUpperCase(),
                      textAlign: TextAlign.center,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 9,
                      ),
                    ),
                    if (player.birthDate != null)
                      Text(
                        '${player.birthDate!.day.toString().padLeft(2, '0')}/${player.birthDate!.month.toString().padLeft(2, '0')}/${player.birthDate!.year}',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 7,
                          color: Colors.grey[600],
                        ),
                      ),
                    if (player.position != null)
                      Text(
                        player.position!,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 7,
                          color: Colors.grey[600],
                        ),
                      ),
                    // Numero matricola
                    if (player.matricola != null)
                      Text(
                        'Mat: ${player.matricola}',
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 6,
                          color: Colors.grey[500],
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.all(2),
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
          staff.name.toUpperCase(), // To uppercase
          style: const TextStyle(
            fontWeight: FontWeight.bold,
            fontSize: 12, // Reduced font size
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
      _showEditPlayerDialog(player);
    }
  }

  void _handleStaffAction(String action, Player staff) {
    if (action == 'delete') {
      _showDeleteStaffDialog(staff);
    } else if (action == 'edit') {
      _showEditStaffDialog(staff);
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

  void _showEditPlayerDialog(Player player) {
    showDialog(
      context: context,
      builder: (context) => EditPlayerDialog(
        player: player,
        onSave: (updatedPlayer) async {
          final playerService = context.read<PlayerService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await playerService.updatePlayer(updatedPlayer);

          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Giocatore aggiornato con successo!')),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(playerService.errorMessage ?? 'Errore nell\'aggiornamento'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }

  void _showEditStaffDialog(Player staff) {
    showDialog(
      context: context,
      builder: (context) => EditStaffDialog(
        staff: staff,
        onSave: (updatedStaff) async {
          final playerService = context.read<PlayerService>();
          final navigator = Navigator.of(context);
          final messenger = ScaffoldMessenger.of(context);
          final success = await playerService.updatePlayer(updatedStaff);

          navigator.pop();
          if (success) {
            messenger.showSnackBar(
              const SnackBar(content: Text('Staff aggiornato con successo!')),
            );
          } else {
            messenger.showSnackBar(
              SnackBar(
                content: Text(playerService.errorMessage ?? 'Errore nell\'aggiornamento'),
                backgroundColor: Colors.red,
              ),
            );
          }
        },
      ),
    );
  }
}