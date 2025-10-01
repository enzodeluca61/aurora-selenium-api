import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../services/auth_service.dart';
import 'matches_calendar_screen.dart';
import 'matches_list_screen.dart';
import 'attendance_screen.dart';
import 'attendance_register_screen.dart';
import 'convocations_screen.dart';
import 'teams_screen.dart';
import 'trainings_screen.dart' as trainings;
import 'fields_screen.dart';
import 'team_management_screen.dart';
import 'messages_screen.dart';
import 'results_screen.dart';
import 'weekend_results_screen.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Aurora Seriate 1967',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        elevation: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: () => _showLogoutDialog(context),
          ),
        ],
      ),
      body: Consumer<AuthService>(
        builder: (context, authService, child) {
          final user = authService.currentUser;
          final userName = user?.userMetadata?['full_name'] ??
                          user?.email?.split('@').first ??
                          'Allenatore';

          return Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: const BoxDecoration(
                  color: Color(0xFF1E3A8A),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(10),
                    bottomRight: Radius.circular(10),
                  ),
                ),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 40,
                      backgroundColor: Colors.white,
                      child: ClipOval(
                        child: Image.asset(
                          'assets/images/aurora_logo.png',
                          width: 70,
                          height: 70,
                          fit: BoxFit.cover,
                          errorBuilder: (context, error, stackTrace) {
                            return Icon(
                              Icons.person,
                              size: 40,
                              color: const Color(0xFF1E3A8A),
                            );
                          },
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      'Benvenuto, $userName',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
              ),


              Expanded(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final screenWidth = constraints.maxWidth;
                      int crossAxisCount;
                      double childAspectRatio;

                      if (screenWidth < 400) {
                        crossAxisCount = 1;
                        childAspectRatio = 3.0;
                      } else if (screenWidth < 600) {
                        crossAxisCount = 2;
                        childAspectRatio = 1.4;
                      } else {
                        crossAxisCount = 3;
                        childAspectRatio = 1.2;
                      }

                      return SingleChildScrollView(
                        child: GridView.count(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          crossAxisCount: crossAxisCount,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                          childAspectRatio: childAspectRatio,
                          children: [
                            _buildModuleCard(
                              context,
                              title: 'CALENDARIO',
                              icon: Icons.event_note,
                              color: Colors.green,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MatchesCalendarScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'LE PARTITE DEL WEEKEND',
                              icon: Icons.sports,
                              color: const Color(0xFF1E3A8A),
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MatchesListScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'RISULTATI',
                              icon: Icons.sports_score,
                              color: Colors.amber,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ResultsScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'PLANNING SETTIMANALE',
                              icon: Icons.schedule,
                              color: Colors.red,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const trainings.TrainingsScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'REGISTRO PRESENZE',
                              icon: Icons.how_to_reg,
                              color: Colors.orange,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AttendanceScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'DISTINTE TORNEI',
                              icon: Icons.emoji_events,
                              color: Colors.purple,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const AttendanceRegisterScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'CONVOCAZIONI',
                              icon: Icons.people_outline,
                              color: Colors.green,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const ConvocationsScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'GESTIONE SQUADRE',
                              icon: Icons.group,
                              color: Colors.teal,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const TeamManagementScreen(),
                                ),
                              ),
                            ),
                            _buildModuleCard(
                              context,
                              title: 'MESSAGGI',
                              icon: Icons.chat_bubble_outline,
                              color: Colors.blue,
                              onTap: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (context) => const MessagesScreen(),
                                ),
                              ),
                            ),
                            // Impostazioni - solo per super admin
                            if (authService.isSuperAdmin)
                              _buildModuleCard(
                                context,
                                title: 'IMPOSTAZIONI',
                                icon: Icons.settings,
                                color: Colors.grey,
                                onTap: () => _showSettingsMenu(context),
                              ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildModuleCard(
    BuildContext context, {
    required String title,
    required IconData icon,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Card(
      elevation: 4,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(15),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(15),
        child: Container(
          padding: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 10 : 12),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(15),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                color.withValues(alpha: 0.1),
                color.withValues(alpha: 0.05),
              ],
            ),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: EdgeInsets.all(MediaQuery.of(context).size.width < 400 ? 12 : 16),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  icon,
                  size: MediaQuery.of(context).size.width < 400 ? 32 : 40,
                  color: color,
                ),
              ),
              SizedBox(height: MediaQuery.of(context).size.width < 400 ? 10 : 15),
              Flexible(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: MediaQuery.of(context).size.width < 400 ? 11 : 13,
                    fontWeight: FontWeight.bold,
                    color: const Color(0xFF1E3A8A),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showLogoutDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Conferma Logout'),
          content: const Text('Sei sicuro di voler uscire dall\'app?'),
          actions: [
            TextButton(
              child: const Text('Annulla'),
              onPressed: () => Navigator.of(context).pop(),
            ),
            TextButton(
              child: const Text('Logout'),
              onPressed: () {
                Navigator.of(context).pop();
                context.read<AuthService>().signOut();
              },
            ),
          ],
        );
      },
    );
  }

  void _showSettingsMenu(BuildContext context) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (BuildContext context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey[300],
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Impostazioni',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),
              ListTile(
                leading: const Icon(
                  Icons.groups,
                  color: Color(0xFF1E3A8A),
                ),
                title: const Text('Squadre 2025-26'),
                subtitle: const Text('Gestisci le squadre Aurora Seriate'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const TeamsScreen(),
                    ),
                  );
                },
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.sports_soccer,
                  color: Color(0xFF1E3A8A),
                ),
                title: const Text('Campi di Allenamento'),
                subtitle: const Text('Gestisci i campi sportivi'),
                trailing: const Icon(Icons.arrow_forward_ios),
                onTap: () {
                  Navigator.of(context).pop();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const FieldsScreen(),
                    ),
                  );
                },
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }
}