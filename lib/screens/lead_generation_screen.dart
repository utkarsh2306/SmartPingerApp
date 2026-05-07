// screens/lead_generation_screen.dart
import 'package:flutter/material.dart';
import 'package:message_me/service/database_service.dart';

class LeadGenerationScreen extends StatefulWidget {
  const LeadGenerationScreen({super.key});

  @override
  State<LeadGenerationScreen> createState() => _LeadGenerationScreenState();
}

class _LeadGenerationScreenState extends State<LeadGenerationScreen> {
  List<Map<String, dynamic>> generatedLeads = [];
  bool loading = false;
  int selectedCount = 0;
  final List<String> leadSources = [
    'Call Logs',
    'Business Directory',
    'Website Visitors',
    'Social Media',
    'Events',
    'Referrals',
  ];
  String selectedSource = 'Call Logs';

  Future<void> generateLeadsFromCallLogs() async {
    setState(() {
      loading = true;
      generatedLeads.clear();
    });

    // Simulate fetching from call logs
    await Future.delayed(const Duration(seconds: 2));

    // Mock data - in real app, fetch from call log
    final mockLeads = [
      {
        'phone': '+919876543210',
        'name': 'Rajesh Kumar',
        'type': 'incoming',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 2))
            .millisecondsSinceEpoch,
      },
      {
        'phone': '+919876543211',
        'name': 'Priya Sharma',
        'type': 'missed',
        'timestamp': DateTime.now()
            .subtract(const Duration(hours: 4))
            .millisecondsSinceEpoch,
      },
      {
        'phone': '+919876543212',
        'name': 'Amit Patel',
        'type': 'outgoing',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 1))
            .millisecondsSinceEpoch,
      },
      {
        'phone': '+919876543213',
        'name': 'Neha Gupta',
        'type': 'incoming',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 2))
            .millisecondsSinceEpoch,
      },
      {
        'phone': '+919876543214',
        'name': 'Sanjay Singh',
        'type': 'missed',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 3))
            .millisecondsSinceEpoch,
      },
      {
        'phone': '+919876543215',
        'name': 'Deepak Verma',
        'type': 'incoming',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 5))
            .millisecondsSinceEpoch,
      },
      {
        'phone': '+919876543216',
        'name': 'Anjali Desai',
        'type': 'outgoing',
        'timestamp': DateTime.now()
            .subtract(const Duration(days: 7))
            .millisecondsSinceEpoch,
      },
    ];

    setState(() {
      generatedLeads = mockLeads;
      loading = false;
    });
  }

  Future<void> saveSelectedLeads() async {
    if (selectedCount == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select leads to save")),
      );
      return;
    }

    final db = await DatabaseService.db;
    int savedCount = 0;

    for (final lead in generatedLeads) {
      if (lead['selected'] == true) {
        final existing = await db.query(
          'leads',
          where: 'phone = ?',
          whereArgs: [lead['phone']],
        );

        if (existing.isEmpty) {
          await db.insert('leads', {
            'phone': lead['phone'],
            'name': lead['name'],
            'type': lead['type'],
            'timestamp': lead['timestamp'],
            'source': selectedSource.toLowerCase().replaceAll(' ', '_'),
            'blocked': 0,
            'count': 1,
          });
          savedCount++;
        }
      }
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text("✓ $savedCount leads saved successfully"),
        backgroundColor: Colors.green,
      ),
    );

    // Clear selection
    for (var lead in generatedLeads) {
      lead['selected'] = false;
    }
    setState(() => selectedCount = 0);
  }

  void selectAllLeads() {
    for (var lead in generatedLeads) {
      lead['selected'] = true;
    }
    setState(() => selectedCount = generatedLeads.length);
  }

  void clearSelection() {
    for (var lead in generatedLeads) {
      lead['selected'] = false;
    }
    setState(() => selectedCount = 0);
  }

  void toggleLead(int index) {
    generatedLeads[index]['selected'] =
        !(generatedLeads[index]['selected'] ?? false);

    selectedCount = generatedLeads
        .where((lead) => lead['selected'] == true)
        .length;

    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Lead Generation"),
        backgroundColor: const Color(0xFF009688),
      ),
      body: Column(
        children: [
          // Source Selection Card
          Card(
            margin: const EdgeInsets.all(16),
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    "Lead Source",
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  const SizedBox(height: 12),
                  DropdownButtonFormField<String>(
                    value: selectedSource,
                    items: leadSources
                        .map(
                          (source) => DropdownMenuItem(
                            value: source,
                            child: Text(source),
                          ),
                        )
                        .toList(),
                    onChanged: (value) =>
                        setState(() => selectedSource = value!),
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      hintText: "Select lead source",
                    ),
                  ),
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: loading ? null : generateLeadsFromCallLogs,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF009688),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                      ),
                      child: loading
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text("GENERATE LEADS"),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Results Section
          Expanded(
            child: generatedLeads.isEmpty
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.people, size: 64, color: Colors.grey[400]),
                        const SizedBox(height: 16),
                        const Text(
                          "No leads generated",
                          style: TextStyle(fontSize: 18, color: Colors.grey),
                        ),
                        const Text(
                          "Select a source and generate leads",
                          style: TextStyle(color: Colors.grey),
                        ),
                      ],
                    ),
                  )
                : Column(
                    children: [
                      // Selection Actions
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "$selectedCount selected",
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF009688),
                              ),
                            ),
                            Row(
                              children: [
                                TextButton(
                                  onPressed: selectAllLeads,
                                  child: const Text("Select All"),
                                ),
                                TextButton(
                                  onPressed: clearSelection,
                                  child: const Text("Clear"),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Leads List
                      Expanded(
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: generatedLeads.length,
                          itemBuilder: (context, index) {
                            final lead = generatedLeads[index];
                            final date = DateTime.fromMillisecondsSinceEpoch(
                              lead['timestamp'] as int,
                            );

                            return Card(
                              margin: const EdgeInsets.only(bottom: 8),
                              child: CheckboxListTile(
                                value: lead['selected'] ?? false,
                                onChanged: (_) => toggleLead(index),
                                title: Text(lead['name']),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(lead['phone']),
                                    const SizedBox(height: 4),
                                    Row(
                                      children: [
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: _getTypeColor(
                                              lead['type'],
                                            ).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            lead['type']
                                                .toString()
                                                .toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _getTypeColor(
                                                lead['type'],
                                              ),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          "${date.day}/${date.month}/${date.year}",
                                          style: const TextStyle(fontSize: 12),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                                secondary: CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF009688,
                                  ).withOpacity(0.1),
                                  child: Text(
                                    lead['name'].toString().substring(0, 1),
                                    style: const TextStyle(
                                      color: Color(0xFF009688),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                      ),

                      // Save Button
                      if (selectedCount > 0)
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton(
                              onPressed: saveSelectedLeads,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF009688),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 16,
                                ),
                              ),
                              child: Text("SAVE $selectedCount LEADS"),
                            ),
                          ),
                        ),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Color _getTypeColor(String type) {
    switch (type.toLowerCase()) {
      case 'incoming':
        return const Color(0xFF4CAF50);
      case 'outgoing':
        return const Color(0xFF2196F3);
      case 'missed':
        return const Color(0xFFF44336);
      default:
        return Colors.grey;
    }
  }
}
