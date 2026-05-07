// screens/old_leads_screen.dart
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/models/lead.dart';

class OldLeadsScreen extends StatefulWidget {
  const OldLeadsScreen({super.key});

  @override
  State<OldLeadsScreen> createState() => _OldLeadsScreenState();
}

class _OldLeadsScreenState extends State<OldLeadsScreen> {
  List<Lead> oldLeads = [];
  List<Lead> filteredLeads = [];
  bool loading = true;
  String searchQuery = '';
  String selectedFilter = 'all'; // all, contacted, not_contacted
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadOldLeads();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> loadOldLeads() async {
    setState(() => loading = true);
    final db = await DatabaseService.db;

    // Get leads older than 30 days
    final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
    final cutoffTimestamp = thirtyDaysAgo.millisecondsSinceEpoch;

    final results = await db.query(
      'leads',
      where: 'timestamp < ? AND blocked = 0',
      whereArgs: [cutoffTimestamp],
      orderBy: 'timestamp DESC',
    );

    setState(() {
      oldLeads = results.map((r) => Lead.fromMap(r)).toList();
      filteredLeads = oldLeads;
      loading = false;
    });
  }

  void _onSearchChanged() {
    setState(() {
      searchQuery = _searchController.text;
      _applyFilters();
    });
  }

  void _applyFilters() {
    List<Lead> results = oldLeads;

    // Apply search filter
    if (searchQuery.isNotEmpty) {
      results = results.where((lead) {
        final phone = lead.phone.toLowerCase();
        final name = lead.name?.toLowerCase() ?? '';
        final query = searchQuery.toLowerCase();
        return phone.contains(query) || name.contains(query);
      }).toList();
    }

    // Apply contact filter
    if (selectedFilter == 'contacted') {
      results = results.where((lead) => lead.lastContacted != null).toList();
    } else if (selectedFilter == 'not_contacted') {
      results = results.where((lead) => lead.lastContacted == null).toList();
    }

    setState(() => filteredLeads = results);
  }

  Future<void> deleteLead(int id) async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete Lead"),
        content: const Text("Are you sure you want to delete this lead?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final db = await DatabaseService.db;
      await db.delete('leads', where: 'id = ?', whereArgs: [id]);
      loadOldLeads();
    }
  }

  Future<void> deleteAllOldLeads() async {
    final confirmed = await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete All Old Leads"),
        content: const Text(
          "This will permanently delete all leads older than 30 days. Continue?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text("Cancel"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text("Delete All"),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final thirtyDaysAgo = DateTime.now().subtract(const Duration(days: 30));
      final cutoffTimestamp = thirtyDaysAgo.millisecondsSinceEpoch;

      final db = await DatabaseService.db;
      await db.delete(
        'leads',
        where: 'timestamp < ? AND blocked = 0',
        whereArgs: [cutoffTimestamp],
      );

      loadOldLeads();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Old Leads (30+ days)"),
        backgroundColor: const Color(0xFF795548),
        actions: [
          if (oldLeads.isNotEmpty)
            IconButton(
              onPressed: deleteAllOldLeads,
              icon: const Icon(Icons.delete_forever),
              tooltip: "Delete All",
            ),
          IconButton(onPressed: loadOldLeads, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : Column(
              children: [
                // Stats Card
                Card(
                  margin: const EdgeInsets.all(16),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "${oldLeads.length} Old Leads",
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              "${filteredLeads.length} shown",
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ],
                        ),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFF795548).withOpacity(0.1),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.history,
                            color: Color(0xFF795548),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                // Search and Filter
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: Column(
                    children: [
                      TextField(
                        controller: _searchController,
                        decoration: InputDecoration(
                          hintText: "Search by name or phone...",
                          prefixIcon: const Icon(Icons.search),
                          suffixIcon: searchQuery.isNotEmpty
                              ? IconButton(
                                  onPressed: () {
                                    _searchController.clear();
                                    _applyFilters();
                                  },
                                  icon: const Icon(Icons.clear),
                                )
                              : null,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            _buildFilterChip("All", 'all'),
                            _buildFilterChip("Contacted", 'contacted'),
                            _buildFilterChip("Not Contacted", 'not_contacted'),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 16),

                // Leads List
                Expanded(
                  child: filteredLeads.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.history,
                                size: 64,
                                color: Colors.grey[400],
                              ),
                              const SizedBox(height: 16),
                              const Text(
                                "No old leads",
                                style: TextStyle(
                                  fontSize: 18,
                                  color: Colors.grey,
                                ),
                              ),
                              const Text(
                                "Leads older than 30 days will appear here",
                                style: TextStyle(color: Colors.grey),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: filteredLeads.length,
                          itemBuilder: (context, index) {
                            final lead = filteredLeads[index];
                            final date = DateTime.fromMillisecondsSinceEpoch(
                              lead.timestamp,
                            );
                            final lastContacted = lead.lastContacted != null
                                ? DateTime.fromMillisecondsSinceEpoch(
                                    lead.lastContacted!,
                                  )
                                : null;
                            final daysOld = DateTime.now()
                                .difference(date)
                                .inDays;

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              child: ListTile(
                                leading: CircleAvatar(
                                  backgroundColor: const Color(
                                    0xFF795548,
                                  ).withOpacity(0.1),
                                  child: Text(
                                    lead.name?.substring(0, 1) ??
                                        lead.phone.substring(0, 1),
                                    style: const TextStyle(
                                      color: Color(0xFF795548),
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                                title: Text(lead.name ?? lead.phone),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(lead.phone),
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
                                              lead.type,
                                            ).withOpacity(0.1),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            lead.type.toUpperCase(),
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: _getTypeColor(lead.type),
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 8,
                                            vertical: 2,
                                          ),
                                          decoration: BoxDecoration(
                                            color: daysOld > 60
                                                ? Colors.red.withOpacity(0.1)
                                                : Colors.orange.withOpacity(
                                                    0.1,
                                                  ),
                                            borderRadius: BorderRadius.circular(
                                              4,
                                            ),
                                          ),
                                          child: Text(
                                            "$daysOld days",
                                            style: TextStyle(
                                              fontSize: 10,
                                              color: daysOld > 60
                                                  ? Colors.red
                                                  : Colors.orange,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (lastContacted != null) ...[
                                      const SizedBox(height: 4),
                                      Text(
                                        "Last contacted: ${DateFormat('dd/MM/yy').format(lastContacted)}",
                                        style: const TextStyle(fontSize: 12),
                                      ),
                                    ],
                                  ],
                                ),
                                trailing: PopupMenuButton(
                                  itemBuilder: (context) => [
                                    const PopupMenuItem(
                                      value: 'delete',
                                      child: Text("Delete Lead"),
                                    ),
                                  ],
                                  onSelected: (value) {
                                    if (value == 'delete' && lead.id != null) {
                                      deleteLead(lead.id!);
                                    }
                                  },
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selectedFilter == value,
        onSelected: (_) {
          setState(() {
            selectedFilter = value;
            _applyFilters();
          });
        },
        selectedColor: const Color(0xFF795548),
        labelStyle: TextStyle(
          color: selectedFilter == value ? Colors.white : Colors.black,
        ),
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
