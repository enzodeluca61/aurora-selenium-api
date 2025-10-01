import 'package:flutter/material.dart';
import 'results_screen.dart';
import '../widgets/submenu_card.dart';

class WeekendResultsScreen extends StatelessWidget {
  const WeekendResultsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text(
          'Risultati del Weekend',
          style: TextStyle(
            fontWeight: FontWeight.bold,
            color: Colors.white,
            fontSize: 14,
          ),
        ),
        centerTitle: true,
        backgroundColor: const Color(0xFF1E3A8A),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 20),

            // Tutti i Risultati
            SubmenuCard(
              title: 'Tutti i Risultati',
              subtitle: 'Visualizza tutti i risultati del weekend',
              icon: Icons.emoji_events,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ResultsScreen(),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Risultati del Sabato
            SubmenuCard(
              title: 'Risultati del Sabato',
              subtitle: 'Risultati delle partite del sabato',
              icon: Icons.wb_sunny,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ResultsScreen(),
                ),
              ),
            ),

            const SizedBox(height: 12),

            // Risultati della Domenica
            SubmenuCard(
              title: 'Risultati della Domenica',
              subtitle: 'Risultati delle partite della domenica',
              icon: Icons.sunny,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const ResultsScreen(),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}