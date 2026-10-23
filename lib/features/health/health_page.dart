import 'package:flutter/material.dart';
import '../../core/design/section.dart';

class HealthPage extends StatelessWidget {
  const HealthPage({super.key});

  @override
  Widget build(BuildContext context) => ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const DemoLabel(),
          const SizedBox(height: 8),
          Text('HEALTH', style: Theme.of(context).textTheme.headlineLarge
              ?.copyWith(fontWeight: FontWeight.w900)),
          const SizedBox(height: 28),
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(26),
              gradient: const LinearGradient(colors: [
                Color(0xFF2E284A), Color(0xFF202C43),
              ]),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('LAST NIGHT / SLEEP',
                    style: TextStyle(color: Color(0xFFD1C2FF),
                        letterSpacing: 1.3)),
                SizedBox(height: 20),
                Text('6h 18m',
                    style: TextStyle(color: Colors.white,
                        fontSize: 42, fontWeight: FontWeight.w900)),
                SizedBox(height: 8),
                Text('Fictional data · simulated Apple Health source',
                    style: TextStyle(color: Color(0xFFD8CEEF))),
              ],
            ),
          ),
          const SizedBox(height: 24),
          const SectionHeading('Connect your sources'),
          const Card(
            child: ListTile(
              leading: Icon(Icons.health_and_safety_outlined),
              title: Text('Health platforms are not connected'),
              subtitle: Text('Permissioned Apple Health and Health Connect '
                  'support will arrive in a later milestone.'),
            ),
          ),
        ],
      );
}
