import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:message_me/service/call_log_service.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/setting_service.dart';
import 'package:message_me/service/sms_service.dart';
import 'package:message_me/service/whatsapp_service.dart';

class StatusScreen extends StatefulWidget {
  final String type;

  const StatusScreen({super.key, required this.type});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  List<Map<String, dynamic>> leads = [];
  List<Map<String, dynamic>> filteredLeads = [];
  bool loading = true;
  String searchQuery = '';
  DateTimeRange? selectedDateRange;
  int daysLimit = 10; // Add this variable

  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadDaysLimit(); // Load saved days limit
    loadData();

    _searchController.addListener(() {
      searchQuery = _searchController.text;
      filterLeads();
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      cleanExistingDuplicates();
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  // Load days limit from settings
  Future<void> _loadDaysLimit() async {
    final days = await SettingsService.getDaysLimit();
    setState(() {
      daysLimit = days;
    });
    await loadData(); // Reload with new days limit
  }

  Future<void> loadData() async {
    setState(() => loading = true);

    // ✅ Save existing message statuses before sync overwrites them
    final db = await DatabaseService.db;
    final existingStatuses = await db.query(
      'leads',
      columns: [
        'phone',
        'timestamp',
        'message_sent',
        'message_status',
        'message_timestamp',
        'message_type',
      ],
      where: 'message_sent = 1',
    );

    // Build a lookup map
    final statusMap = <String, Map<String, dynamic>>{};
    for (var row in existingStatuses) {
      final key = '${row['phone']}_${row['timestamp']}';
      statusMap[key] = row;
    }

    await CallLogService.syncLogs(widget.type.toLowerCase());

    final daysAgo = DateTime.now()
        .subtract(Duration(days: daysLimit))
        .millisecondsSinceEpoch;

    final result = await db.query(
      'leads',
      where: 'type = ? AND blocked = 0 AND timestamp >= ?',
      whereArgs: [widget.type.toLowerCase(), daysAgo],
      orderBy: 'timestamp DESC',
    );

    // ✅ Restore message statuses that sync may have wiped
    for (var status in statusMap.values) {
      final key = '${status['phone']}_${status['timestamp']}';
      if (statusMap.containsKey(key)) {
        await db.update(
          'leads',
          {
            'message_sent': status['message_sent'],
            'message_status': status['message_status'],
            'message_timestamp': status['message_timestamp'],
            'message_type': status['message_type'],
          },
          where: 'phone = ? AND timestamp = ?',
          whereArgs: [status['phone'], status['timestamp']],
        );
      }
    }

    // Re-fetch with restored statuses
    final finalResult = await db.query(
      'leads',
      where: 'type = ? AND blocked = 0 AND timestamp >= ?',
      whereArgs: [widget.type.toLowerCase(), daysAgo],
      orderBy: 'timestamp DESC',
    );

    final uniqueLeads = <Map<String, dynamic>>[];
    final seenKeys = <String>{};
    for (var lead in finalResult) {
      final key = '${lead['phone']}_${lead['timestamp']}';
      if (!seenKeys.contains(key)) {
        seenKeys.add(key);
        uniqueLeads.add(lead);
      }
    }

    setState(() {
      leads = uniqueLeads;
      filteredLeads = uniqueLeads;
      loading = false;
    });
  }

  Future<void> cleanExistingDuplicates() async {
    final db = await DatabaseService.db;

    final daysAgo = DateTime.now()
        .subtract(Duration(days: daysLimit))
        .millisecondsSinceEpoch;

    final allLeads = await db.query(
      'leads',
      where: 'timestamp >= ?',
      whereArgs: [daysAgo],
    );

    final Map<String, List<Map<String, dynamic>>> groups = {};

    for (var lead in allLeads) {
      final key = '${lead['phone']}_${lead['type']}_${lead['timestamp']}';
      if (!groups.containsKey(key)) {
        groups[key] = [];
      }
      groups[key]!.add(lead);
    }

    int deletedCount = 0;

    for (var entries in groups.entries) {
      if (entries.value.length > 1) {
        for (int i = 1; i < entries.value.length; i++) {
          await db.delete(
            'leads',
            where: 'id = ?',
            whereArgs: [entries.value[i]['id']],
          );
          deletedCount++;
        }
      }
    }

    await loadData();

    if (mounted && deletedCount > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Removed $deletedCount duplicate entries'),
          backgroundColor: Colors.green,
        ),
      );
    }
  }

  Future<void> selectDateRange(BuildContext context) async {
    final daysAgo = DateTime.now().subtract(Duration(days: daysLimit));

    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: daysAgo,
      lastDate: DateTime.now(),
      initialDateRange:
          selectedDateRange ??
          DateTimeRange(
            start: DateTime.now().subtract(const Duration(days: 7)),
            end: DateTime.now(),
          ),
    );

    if (picked != null && picked != selectedDateRange) {
      setState(() {
        selectedDateRange = picked;
        filterLeads();
      });
    }
  }

  void filterLeads() {
    var result = leads;

    if (searchQuery.isNotEmpty) {
      result = result.where((lead) {
        final phone = lead['phone']?.toString().toLowerCase() ?? '';
        return phone.contains(searchQuery.toLowerCase());
      }).toList();
    }

    if (selectedDateRange != null) {
      result = result.where((lead) {
        final timestamp = lead['timestamp'] as int?;
        if (timestamp == null) return false;

        final date = DateTime.fromMillisecondsSinceEpoch(timestamp);

        return date.isAfter(selectedDateRange!.start) &&
            date.isBefore(selectedDateRange!.end.add(const Duration(days: 1)));
      }).toList();
    } else {
      final daysAgo = DateTime.now()
          .subtract(Duration(days: daysLimit))
          .millisecondsSinceEpoch;
      result = result.where((lead) {
        final timestamp = lead['timestamp'] as int?;
        if (timestamp == null) return false;
        return timestamp >= daysAgo;
      }).toList();
    }

    setState(() => filteredLeads = result);
  }

  Color getStatusColor() {
    switch (widget.type.toLowerCase()) {
      case 'incoming':
        return const Color(0xFF22C55E);
      case 'outgoing':
        return const Color(0xFF3B82F6);
      case 'missed':
        return const Color(0xFFEF4444);
      default:
        return const Color(0xFF6B7280);
    }
  }

  IconData getStatusIcon() {
    switch (widget.type.toLowerCase()) {
      case 'incoming':
        return Icons.call_received_rounded;
      case 'outgoing':
        return Icons.call_made_rounded;
      case 'missed':
        return Icons.call_missed_rounded;
      default:
        return Icons.call_rounded;
    }
  }

  String getStatusTitle() {
    switch (widget.type.toLowerCase()) {
      case 'incoming':
        return 'Incoming Calls';
      case 'outgoing':
        return 'Outgoing Calls';
      case 'missed':
        return 'Missed Calls';
      default:
        return 'Call Logs';
    }
  }

  void _showDaysLimitDialog() {
    final daysOptions = SettingsService.getDaysOptions();

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Days Limit',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text(
                'Select how many days of call records to show:',
                style: TextStyle(fontSize: 14),
              ),
              const SizedBox(height: 16),
              ...daysOptions.map((days) {
                return RadioListTile<int>(
                  title: Text('Last $days days'),
                  value: days,
                  groupValue: daysLimit,
                  activeColor: getStatusColor(),
                  onChanged: (value) async {
                    if (value != null) {
                      await SettingsService.setDaysLimit(value);
                      Navigator.pop(context);
                      _loadDaysLimit();
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Showing last $value days of records'),
                          behavior: SnackBarBehavior.floating,
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    }
                  },
                );
              }),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  Future<void> _showSmsSheet(Map<String, dynamic> lead) async {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(24),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 48,
                height: 5,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(100),
                ),
              ),
              const SizedBox(height: 24),
              Container(
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: getStatusColor().withOpacity(.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.send_rounded,
                  size: 32,
                  color: getStatusColor(),
                ),
              ),
              const SizedBox(height: 18),
              const Text(
                'Send Message',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 10),
              Text(
                lead['phone'] ?? '',
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey.shade700,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                'Choose how you want to send your message',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.grey.shade600, height: 1.5),
              ),
              const SizedBox(height: 20),

              _MessageOption(
                icon: Icons.message_rounded,
                title: 'SMS',
                subtitle: 'Send via default SMS app',
                color: getStatusColor(),
                onTap: () async {
                  Navigator.pop(context);
                  await _sendSms(lead);
                },
              ),

              _MessageOption(
                icon: Icons.apps_rounded,
                title: 'More Apps',
                subtitle: 'WhatsApp, Telegram, Messenger, etc.',
                color: Colors.grey,
                onTap: () async {
                  Navigator.pop(context);
                  await _sendWithAppSelection(lead);
                },
              ),

              const SizedBox(height: 16),
            ],
          ),
        );
      },
    );
  }

  Future<void> _sendWithAppSelection(Map<String, dynamic> lead) async {
    await MultiAppMessagingService.sendMessage(
      context: context,
      phoneNumber: lead['phone'],
      message: 'Hello, this is a follow-up message from SMS Marketing.',
    );
  }

  Future<void> _sendSms(Map<String, dynamic> lead) async {
    try {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 12),
                Text('Sending SMS...'),
              ],
            ),
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 2),
          ),
        );
      }

      await SmsService.send(
        lead['phone'],
        'Hello, this is a follow-up message from SMS Marketing.',
      );

      final db = await DatabaseService.db;
      final now = DateTime.now().millisecondsSinceEpoch;

      // ✅ Update by phone + timestamp, not just id (id can change after sync)
      await db.update(
        'leads',
        {
          'last_contacted': now,
          'message_sent': 1,
          'message_status': 'sent',
          'message_timestamp': now,
          'message_type': 'sms',
        },
        where: 'phone = ? AND timestamp = ?',
        whereArgs: [lead['phone'], lead['timestamp']],
      );

      // ✅ Update local list directly without full reload
      setState(() {
        final index = filteredLeads.indexWhere(
          (l) =>
              l['phone'] == lead['phone'] &&
              l['timestamp'] == lead['timestamp'],
        );
        if (index != -1) {
          filteredLeads[index] = {
            ...filteredLeads[index],
            'message_sent': 1,
            'message_status': 'sent',
            'message_timestamp': now,
            'message_type': 'sms',
          };
        }
      });

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.green,
            content: Row(
              children: [
                const Icon(Icons.check_circle_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(
                  child: Text('SMS sent successfully to ${lead['phone']}'),
                ),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      final db = await DatabaseService.db;
      await db.update(
        'leads',
        {
          'message_sent': 0,
          'message_status': 'failed',
          'message_error': e.toString(),
          'message_timestamp': DateTime.now().millisecondsSinceEpoch,
        },
        where: 'phone = ? AND timestamp = ?',
        whereArgs: [lead['phone'], lead['timestamp']],
      );

      if (mounted) {
        ScaffoldMessenger.of(context).clearSnackBars();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            behavior: SnackBarBehavior.floating,
            backgroundColor: Colors.red,
            content: Row(
              children: [
                const Icon(Icons.error_rounded, color: Colors.white),
                const SizedBox(width: 12),
                Expanded(child: Text('Failed to send SMS: $e')),
              ],
            ),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    }
  }

  Widget _buildMessageStatusBadge(Map<String, dynamic> lead) {
    final messageSent = lead['message_sent'] == 1;
    final messageStatus = lead['message_status'];
    final messageType = lead['message_type'];

    if (!messageSent) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.send_rounded, size: 14, color: Colors.grey.shade500),
            const SizedBox(width: 4),
            Text(
              'Not Sent',
              style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
            ),
          ],
        ),
      );
    }

    if (messageStatus == 'sent') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.green.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.green.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.check_circle_rounded, size: 14, color: Colors.green),
            const SizedBox(width: 4),
            Text(
              'Sent via ${messageType?.toUpperCase() ?? 'SMS'}',
              style: TextStyle(fontSize: 11, color: Colors.green.shade700),
            ),
          ],
        ),
      );
    }

    if (messageStatus == 'failed') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.red.shade50,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: Colors.red.shade200),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 14, color: Colors.red),
            const SizedBox(width: 4),
            Text(
              'Failed',
              style: TextStyle(fontSize: 11, color: Colors.red.shade700),
            ),
          ],
        ),
      );
    }

    return const SizedBox.shrink();
  }

  String _getLastMessageTime(Map<String, dynamic> lead) {
    final timestamp = lead['message_timestamp'];
    if (timestamp == null) return '';

    final date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inMinutes < 1) {
      return 'Just now';
    } else if (difference.inHours < 1) {
      return '${difference.inMinutes}m ago';
    } else if (difference.inDays < 1) {
      return '${difference.inHours}h ago';
    } else if (difference.inDays < 7) {
      return '${difference.inDays}d ago';
    } else {
      return DateFormat('dd MMM').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF4F6FA),
      appBar: AppBar(
        backgroundColor: getStatusColor(),
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              getStatusTitle(),
              style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              '${filteredLeads.length} leads (Last $daysLimit days)',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 8),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: IconButton(
              onPressed: () => _showDaysLimitDialog(),
              icon: const Icon(Icons.settings_rounded, size: 20),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(),
            ),
          ),
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(getStatusIcon(), color: Colors.white, size: 20),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(.15),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: TextField(
                      controller: _searchController,
                      style: const TextStyle(color: Colors.white, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Search...',
                        hintStyle: TextStyle(
                          color: Colors.white.withOpacity(.7),
                          fontSize: 14,
                        ),
                        prefixIcon: const Icon(
                          Icons.search_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                        suffixIcon: searchQuery.isNotEmpty
                            ? IconButton(
                                onPressed: () => _searchController.clear(),
                                icon: const Icon(
                                  Icons.close_rounded,
                                  color: Colors.white,
                                  size: 20,
                                ),
                              )
                            : null,
                        border: InputBorder.none,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: IconButton(
                    onPressed: loadData,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                      size: 20,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 18, 20, 14),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(16),
                    onTap: () => selectDateRange(context),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 14,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(.04),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.calendar_month_rounded,
                            color: getStatusColor(),
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Text(
                            selectedDateRange == null
                                ? 'Filter by Date (Last $daysLimit days)'
                                : '${DateFormat('dd MMM').format(selectedDateRange!.start)} - ${DateFormat('dd MMM').format(selectedDateRange!.end)}',
                            style: const TextStyle(fontWeight: FontWeight.w600),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Container(
                  decoration: BoxDecoration(
                    color: getStatusColor(),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: IconButton(
                    onPressed: loadData,
                    icon: const Icon(
                      Icons.refresh_rounded,
                      color: Colors.white,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: loading
                ? Center(
                    child: CircularProgressIndicator(color: getStatusColor()),
                  )
                : filteredLeads.isEmpty
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 32),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Container(
                            padding: const EdgeInsets.all(26),
                            decoration: BoxDecoration(
                              color: getStatusColor().withOpacity(.12),
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              getStatusIcon(),
                              size: 54,
                              color: getStatusColor(),
                            ),
                          ),
                          const SizedBox(height: 20),
                          const Text(
                            'No Calls Found',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Text(
                            'No records found in the last $daysLimit days.\nTry changing your filters or refresh the list.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: Colors.grey.shade600,
                              height: 1.5,
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    itemCount: filteredLeads.length,
                    itemBuilder: (context, index) {
                      final lead = filteredLeads[index];
                      final timestamp = lead['timestamp'] as int?;
                      final date = timestamp != null
                          ? DateTime.fromMillisecondsSinceEpoch(timestamp)
                          : DateTime.now();
                      final messageSent = lead['message_sent'] == 1;

                      return Container(
                        margin: const EdgeInsets.only(bottom: 16),
                        child: Material(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(24),
                          child: InkWell(
                            borderRadius: BorderRadius.circular(24),
                            onTap: () => _showSmsSheet(lead),
                            child: Container(
                              padding: const EdgeInsets.all(18),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(24),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(.04),
                                    blurRadius: 14,
                                    offset: const Offset(0, 6),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  Container(
                                    width: 58,
                                    height: 58,
                                    decoration: BoxDecoration(
                                      color: getStatusColor().withOpacity(.12),
                                      borderRadius: BorderRadius.circular(18),
                                    ),
                                    child: Icon(
                                      getStatusIcon(),
                                      color: getStatusColor(),
                                    ),
                                  ),
                                  const SizedBox(width: 16),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                lead['phone'] ?? 'Unknown',
                                                style: const TextStyle(
                                                  fontSize: 17,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                            if (messageSent) ...[
                                              const SizedBox(width: 8),
                                              Icon(
                                                Icons.check_circle_rounded,
                                                size: 16,
                                                color: Colors.green.shade500,
                                              ),
                                            ],
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(
                                              Icons.call_rounded,
                                              size: 12,
                                              color: Colors.grey.shade500,
                                            ),
                                            const SizedBox(width: 4),
                                            Text(
                                              DateFormat(
                                                'dd MMM yyyy • hh:mm a',
                                              ).format(date),
                                              style: TextStyle(
                                                color: Colors.grey.shade600,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            _buildMessageStatusBadge(lead),
                                            if (messageSent) ...[
                                              const SizedBox(width: 8),
                                              Text(
                                                _getLastMessageTime(lead),
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  color: Colors.grey.shade500,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.all(12),
                                    decoration: BoxDecoration(
                                      color: messageSent
                                          ? Colors.green.shade100
                                          : getStatusColor(),
                                      borderRadius: BorderRadius.circular(16),
                                    ),
                                    child: Icon(
                                      messageSent
                                          ? Icons.check_rounded
                                          : Icons.sms_rounded,
                                      color: messageSent
                                          ? Colors.green.shade700
                                          : Colors.white,
                                      size: 20,
                                    ),
                                  ),
                                ],
                              ),
                            ),
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
}

class _MessageOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _MessageOption({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(16),
      ),
      child: ListTile(
        onTap: onTap,
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Icon(icon, color: color, size: 24),
        ),
        title: Text(
          title,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        subtitle: Text(
          subtitle,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
        trailing: const Icon(Icons.chevron_right_rounded, color: Colors.grey),
      ),
    );
  }
}
