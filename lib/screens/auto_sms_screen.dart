import 'package:flutter/material.dart';
import 'package:message_me/models/message_template.dart';
import 'package:message_me/service/background_service.dart';
import 'package:message_me/service/database_service.dart';

class AutoSmsScreen extends StatefulWidget {
  const AutoSmsScreen({super.key});

  @override
  State<AutoSmsScreen> createState() => _AutoSmsScreenState();
}

class AutoSmsRule {
  final int? id;
  final String name;
  final String triggerType;
  final int delayMinutes;
  final int? templateId;
  final String? customMessage;
  final bool isActive;
  final DateTime createdAt;

  AutoSmsRule({
    this.id,
    required this.name,
    required this.triggerType,
    this.delayMinutes = 0,
    this.templateId,
    this.customMessage,
    this.isActive = true,
    DateTime? createdAt,
  }) : createdAt = createdAt ?? DateTime.now();

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'name': name,
      'trigger_type': triggerType,
      'delay_minutes': delayMinutes,
      'template_id': templateId,
      'custom_message': customMessage,
      'is_active': isActive ? 1 : 0,
      'created_at': createdAt.millisecondsSinceEpoch,
    };
  }
}

class _AutoSmsScreenState extends State<AutoSmsScreen> {
  List<AutoSmsRule> rules = [];
  List<MessageTemplate> templates = [];
  bool loading = true;

  final TextEditingController _nameController = TextEditingController();
  final TextEditingController _customMessageController =
      TextEditingController();

  String selectedTrigger = 'missed';
  int selectedDelay = 0;
  int? selectedTemplateId;
  bool useCustomMessage = false;

  final Color primaryColor = const Color(0xFF6C63FF);

  @override
  void initState() {
    super.initState();
    loadData();
  }

  @override
  void dispose() {
    _nameController.dispose();
    _customMessageController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() => loading = true);
    final db = await DatabaseService.db;

    final ruleResults = await db.query(
      'auto_sms_rules',
      orderBy: 'created_at DESC',
    );
    rules = ruleResults
        .map(
          (r) => AutoSmsRule(
            id: r['id'] as int?,
            name: r['name'] as String,
            triggerType: r['trigger_type'] as String,
            delayMinutes: r['delay_minutes'] as int,
            templateId: r['template_id'] as int?,
            customMessage: r['custom_message'] as String?,
            isActive: r['is_active'] == 1,
            createdAt: DateTime.fromMillisecondsSinceEpoch(
              r['created_at'] as int,
            ),
          ),
        )
        .toList();

    final templateResults = await db.query('templates');
    templates = templateResults.map((e) => MessageTemplate.fromMap(e)).toList();

    setState(() => loading = false);
  }

  Future<void> _saveRule({int? editId}) async {
    if (_nameController.text.trim().isEmpty) {
      _showSnack('Please enter a rule name', Colors.red);
      return;
    }
    if (!useCustomMessage && selectedTemplateId == null) {
      _showSnack(
        'Please select a template or write a custom message',
        Colors.red,
      );
      return;
    }
    if (useCustomMessage && _customMessageController.text.trim().isEmpty) {
      _showSnack('Please enter a custom message', Colors.red);
      return;
    }

    final db = await DatabaseService.db;
    final data = {
      'name': _nameController.text.trim(),
      'trigger_type': selectedTrigger,
      'delay_minutes': selectedDelay,
      'template_id': useCustomMessage ? null : selectedTemplateId,
      'custom_message': useCustomMessage
          ? _customMessageController.text.trim()
          : null,
      'is_active': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
    };

    if (editId != null) {
      await db.update(
        'auto_sms_rules',
        data,
        where: 'id = ?',
        whereArgs: [editId],
      );
      _showSnack('Rule updated successfully', Colors.green);
    } else {
      await db.insert('auto_sms_rules', data);
      _showSnack('Rule created successfully', Colors.green);
    }

    _resetForm();
    await loadData();
    await BackgroundServiceManager.syncRulesToNative();
  }

  void _resetForm() {
    _nameController.clear();
    _customMessageController.clear();
    selectedTrigger = 'missed';
    selectedDelay = 0;
    selectedTemplateId = null;
    useCustomMessage = false;
  }

  void _showSnack(String msg, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
  }

  Future<void> toggleRule(int id, bool isActive) async {
    final db = await DatabaseService.db;
    await db.update(
      'auto_sms_rules',
      {'is_active': isActive ? 0 : 1},
      where: 'id = ?',
      whereArgs: [id],
    );
    await BackgroundServiceManager.syncRulesToNative();

    loadData();
  }

  Future<void> deleteRule(int id) async {
    final confirm = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.delete_outline_rounded,
                color: Colors.red,
                size: 32,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Delete rule?',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 8),
            Text(
              'This action cannot be undone.',
              style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(context, true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      foregroundColor: Colors.white,
                      minimumSize: const Size.fromHeight(50),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Delete'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    if (confirm == true) {
      final db = await DatabaseService.db;
      await db.delete('auto_sms_rules', where: 'id = ?', whereArgs: [id]);
      await BackgroundServiceManager.syncRulesToNative();
      loadData();
    }
  }

  void _showRuleSheet({AutoSmsRule? editRule}) {
    // Pre-fill if editing
    if (editRule != null) {
      _nameController.text = editRule.name;
      selectedTrigger = editRule.triggerType;
      selectedDelay = editRule.delayMinutes;
      selectedTemplateId = editRule.templateId;
      useCustomMessage = editRule.customMessage != null;
      if (editRule.customMessage != null) {
        _customMessageController.text = editRule.customMessage!;
      }
    } else {
      _resetForm();
    }

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setModalState) => Container(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 24,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle
                Center(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Title
                Text(
                  editRule != null ? 'Edit rule' : 'Create auto SMS rule',
                  style: const TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Automatically send messages based on call activity.',
                  style: TextStyle(color: Colors.grey.shade600, fontSize: 14),
                ),
                const SizedBox(height: 24),

                // Rule Name
                _SheetLabel('Rule name'),
                const SizedBox(height: 8),
                TextField(
                  controller: _nameController,
                  decoration: _inputDecoration(
                    'e.g. Missed call reply',
                    Icons.edit_rounded,
                  ),
                ),
                const SizedBox(height: 16),

                // Trigger Type
                _SheetLabel('Trigger type'),
                const SizedBox(height: 8),
                Container(
                  decoration: _dropdownDecoration(),
                  child: DropdownButtonFormField<String>(
                    value: selectedTrigger,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: Icon(Icons.bolt_rounded),
                    ),
                    items: const [
                      DropdownMenuItem(
                        value: 'missed',
                        child: Text('Missed call'),
                      ),
                      DropdownMenuItem(
                        value: 'incoming',
                        child: Text('Incoming call'),
                      ),
                      DropdownMenuItem(
                        value: 'outgoing',
                        child: Text('Outgoing call'),
                      ),
                    ],
                    onChanged: (v) => setModalState(() => selectedTrigger = v!),
                  ),
                ),
                const SizedBox(height: 16),

                // Delay
                _SheetLabel('Send delay'),
                const SizedBox(height: 8),
                Container(
                  decoration: _dropdownDecoration(),
                  child: DropdownButtonFormField<int>(
                    menuMaxHeight: 300,
                    value: selectedDelay,
                    decoration: const InputDecoration(
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 14,
                      ),
                      prefixIcon: Icon(Icons.schedule_rounded),
                    ),
                    items: [0, 1, 5, 10, 15, 30, 60]
                        .map(
                          (e) => DropdownMenuItem(
                            value: e,
                            child: Text(e == 0 ? 'Immediate' : '$e minutes'),
                          ),
                        )
                        .toList(),
                    onChanged: (v) => setModalState(() => selectedDelay = v!),
                  ),
                ),
                const SizedBox(height: 16),

                // Message Source
                _SheetLabel('Message'),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFFF5F7FB),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      // Template option
                      InkWell(
                        onTap: () => setModalState(() {
                          useCustomMessage = false;
                          selectedTemplateId = null;
                        }),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              _RadioDot(
                                selected: !useCustomMessage,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Use a template',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Template dropdown
                      if (!useCustomMessage)
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: DropdownButtonFormField<int?>(
                            value: selectedTemplateId,
                            isExpanded: true,
                            decoration: const InputDecoration(
                              border: InputBorder.none,
                              contentPadding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 12,
                              ),
                            ),
                            hint: Text(
                              'Select a template...',
                              style: TextStyle(
                                color: Colors.grey.shade500,
                                fontSize: 14,
                              ),
                            ),
                            items: [
                              const DropdownMenuItem<int?>(
                                value: null,
                                child: Text(
                                  'Select a template...',
                                  style: TextStyle(fontSize: 14),
                                ),
                              ),
                              ...templates.map(
                                (t) => DropdownMenuItem<int?>(
                                  value: t.id,
                                  child: Text(
                                    t.title,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                    maxLines: 1,
                                  ),
                                ),
                              ),
                            ],
                            onChanged: (v) =>
                                setModalState(() => selectedTemplateId = v),
                          ),
                        ),
                      // After the DropdownButtonFormField, add this:
                      if (selectedTemplateId != null) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.preview_rounded,
                                size: 14,
                                color: Colors.grey.shade400,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  // find the selected template message
                                  templates
                                      .firstWhere(
                                        (t) => t.id == selectedTemplateId,
                                        orElse: () => MessageTemplate(
                                          title: '',
                                          message: '',
                                        ),
                                      )
                                      .message,
                                  style: TextStyle(
                                    fontSize: 12,
                                    color: Colors.grey.shade600,
                                    height: 1.5,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      // Divider
                      Divider(height: 1, color: Colors.grey.shade200),

                      // Custom message option
                      InkWell(
                        onTap: () => setModalState(() {
                          useCustomMessage = true;
                          selectedTemplateId = null;
                        }),
                        borderRadius: const BorderRadius.vertical(
                          bottom: Radius.circular(16),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 14,
                          ),
                          child: Row(
                            children: [
                              _RadioDot(
                                selected: useCustomMessage,
                                color: primaryColor,
                              ),
                              const SizedBox(width: 12),
                              const Text(
                                'Write custom message',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),

                      // Custom message field
                      if (useCustomMessage)
                        Container(
                          margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                          decoration: BoxDecoration(
                            color: Colors.white,
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.grey.shade200),
                          ),
                          child: TextField(
                            controller: _customMessageController,
                            maxLines: 4,
                            minLines: 3,
                            decoration: InputDecoration(
                              hintText: 'Type your message here...',
                              hintStyle: TextStyle(
                                color: Colors.grey.shade400,
                                fontSize: 14,
                              ),
                              border: InputBorder.none,
                              contentPadding: const EdgeInsets.all(14),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),

                const SizedBox(height: 28),

                // Create / Save button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () async {
                      await _saveRule(editId: editRule?.id);
                      if (mounted) Navigator.pop(context);
                    },
                    style: ElevatedButton.styleFrom(
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      backgroundColor: primaryColor,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                    ),
                    child: Text(
                      editRule != null ? 'Save changes' : 'Create rule',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(String hint, IconData icon) {
    return InputDecoration(
      hintText: hint,
      prefixIcon: Icon(icon),
      filled: true,
      fillColor: const Color(0xFFF5F7FB),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide.none,
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
    );
  }

  BoxDecoration _dropdownDecoration() {
    return BoxDecoration(
      color: const Color(0xFFF5F7FB),
      borderRadius: BorderRadius.circular(16),
    );
  }

  String _formatTrigger(String value) {
    switch (value) {
      case 'incoming':
        return 'Incoming call';
      case 'outgoing':
        return 'Outgoing call';
      default:
        return 'Missed call';
    }
  }

  IconData _triggerIcon(String value) {
    switch (value) {
      case 'incoming':
        return Icons.call_received_rounded;
      case 'outgoing':
        return Icons.call_made_rounded;
      default:
        return Icons.call_missed_rounded;
    }
  }

  Color _triggerColor(String value) {
    switch (value) {
      case 'incoming':
        return const Color(0xFF22C55E);
      case 'outgoing':
        return const Color(0xFF3B82F6);
      default:
        return const Color(0xFFEF4444);
    }
  }

  String _getMessagePreview(AutoSmsRule rule) {
    if (rule.customMessage != null && rule.customMessage!.isNotEmpty) {
      return rule.customMessage!;
    }
    final template = templates.firstWhere(
      (t) => t.id == rule.templateId,
      orElse: () => MessageTemplate(title: 'No template', message: ''),
    );
    return template.message;
  }

  String _getTemplateTitle(AutoSmsRule rule) {
    if (rule.customMessage != null) return 'Custom message';
    final template = templates.firstWhere(
      (t) => t.id == rule.templateId,
      orElse: () => MessageTemplate(title: 'No template', message: ''),
    );
    return template.title;
  }

  @override
  Widget build(BuildContext context) {
    final activeCount = rules.where((r) => r.isActive).length;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          onPressed: () => Navigator.pop(context),
          icon: const Icon(Icons.arrow_back_ios_new_rounded),
        ),
        title: const Text(
          'Auto SMS rules',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 20),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(.15),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(
              Icons.auto_awesome_rounded,
              color: Colors.white,
              size: 20,
            ),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(50),
          child: Container(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(
                    Icons.auto_awesome_rounded,
                    size: 18,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 12),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '$activeCount rule${activeCount == 1 ? '' : 's'} active',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    const Text(
                      'Automate SMS on call events',
                      style: TextStyle(color: Colors.white70, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator())
          : rules.isEmpty
          ? _buildEmpty()
          : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              itemCount: rules.length,
              itemBuilder: (context, index) => _buildRuleCard(rules[index]),
            ),
      floatingActionButton: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        width: double.infinity,
        child: FloatingActionButton.extended(
          onPressed: () => _showRuleSheet(),
          backgroundColor: primaryColor,
          elevation: 4,
          icon: const Icon(Icons.add_rounded, color: Colors.white),
          label: const Text(
            'Add rule',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.w600,
              fontSize: 15,
            ),
          ),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: primaryColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.auto_awesome_rounded,
                size: 52,
                color: primaryColor,
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              'No rules yet',
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Create your first rule to automatically send SMS after missed, incoming, or outgoing calls.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.grey.shade600,
                height: 1.6,
                fontSize: 14,
              ),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: () => _showRuleSheet(),
              icon: const Icon(Icons.add_rounded),
              label: const Text('Create first rule'),
              style: ElevatedButton.styleFrom(
                backgroundColor: primaryColor,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 14,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRuleCard(AutoSmsRule rule) {
    final triggerColor = _triggerColor(rule.triggerType);
    final messagePreview = _getMessagePreview(rule);
    final isCustom = rule.customMessage != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: rule.isActive
              ? primaryColor.withOpacity(0.12)
              : Colors.grey.shade200,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: rule.isActive
                        ? triggerColor.withOpacity(0.12)
                        : Colors.grey.shade100,
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    _triggerIcon(rule.triggerType),
                    color: rule.isActive ? triggerColor : Colors.grey,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        rule.name,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: rule.isActive
                              ? const Color(0xFF1E293B)
                              : Colors.grey.shade500,
                        ),
                      ),
                      const SizedBox(height: 5),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: rule.isActive
                              ? triggerColor.withOpacity(0.1)
                              : Colors.grey.shade100,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _formatTrigger(rule.triggerType),
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: rule.isActive ? triggerColor : Colors.grey,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  value: rule.isActive,
                  activeColor: primaryColor,
                  onChanged: (_) => toggleRule(rule.id!, rule.isActive),
                ),
              ],
            ),
          ),

          // ── Meta info ──
          Container(
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: const Color(0xFFF8F9FB),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                // Delay row
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: rule.isActive
                            ? primaryColor.withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        Icons.schedule_rounded,
                        size: 16,
                        color: rule.isActive ? primaryColor : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Delay',
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade500,
                          ),
                        ),
                        Text(
                          rule.delayMinutes == 0
                              ? 'Immediate'
                              : '${rule.delayMinutes} min',
                          style: const TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),

                const SizedBox(height: 10),
                Divider(height: 1, color: Colors.grey.shade200),
                const SizedBox(height: 10),

                // Message row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      decoration: BoxDecoration(
                        color: rule.isActive
                            ? primaryColor.withOpacity(0.1)
                            : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        isCustom ? Icons.edit_rounded : Icons.message_rounded,
                        size: 16,
                        color: rule.isActive ? primaryColor : Colors.grey,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isCustom ? 'Custom message' : 'Template',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.grey.shade500,
                            ),
                          ),
                          Text(
                            _getTemplateTitle(rule),
                            style: const TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (messagePreview.isNotEmpty) ...[
                            const SizedBox(height: 6),
                            Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: Colors.white,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.grey.shade200),
                              ),
                              child: Text(
                                messagePreview.length > 80
                                    ? '${messagePreview.substring(0, 80)}...'
                                    : messagePreview,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.grey.shade600,
                                  height: 1.5,
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          // ── Actions ──
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => _showRuleSheet(editRule: rule),
                    icon: const Icon(Icons.edit_rounded, size: 16),
                    label: const Text('Edit'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: primaryColor,
                      side: BorderSide(color: primaryColor.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () => deleteRule(rule.id!),
                    icon: const Icon(Icons.delete_outline_rounded, size: 16),
                    label: const Text('Delete'),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: BorderSide(color: Colors.red.withOpacity(0.3)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
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
}

// ── Helper widgets ──

class _SheetLabel extends StatelessWidget {
  final String text;
  const _SheetLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        color: Color(0xFF64748B),
      ),
    );
  }
}

class _RadioDot extends StatelessWidget {
  final bool selected;
  final Color color;
  const _RadioDot({required this.selected, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 20,
      height: 20,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(
          color: selected ? color : Colors.grey.shade400,
          width: 1.5,
        ),
      ),
      child: selected
          ? Center(
              child: Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(shape: BoxShape.circle, color: color),
              ),
            )
          : null,
    );
  }
}

class _InfoRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(icon, size: 18, color: color),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: const TextStyle(
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
