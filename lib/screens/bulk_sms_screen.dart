import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:message_me/models/message_template.dart';
import 'package:message_me/service/database_service.dart';
import 'package:message_me/service/sms_service.dart';
import 'package:message_me/service/whatsapp_service.dart';

class BulkSmsScreen extends StatefulWidget {
  const BulkSmsScreen({super.key});

  @override
  State<BulkSmsScreen> createState() => _BulkSmsScreenState();
}

class _BulkSmsScreenState extends State<BulkSmsScreen> {
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _messageController = TextEditingController();

  List<Map<String, dynamic>> allLeads = [];
  List<MessageTemplate> templates = [];
  MessageTemplate? selectedTemplate;

  bool loading = true;
  bool sending = false;
  int sentCount = 0;
  int failedCount = 0;
  String selectedApp = 'sms';

  static const _primary = Color(0xFF00BCD4);

  @override
  void initState() {
    super.initState();
    _messageController.addListener(() => setState(() {}));
    loadData();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  Future<void> loadData() async {
    setState(() => loading = true);
    final db = await DatabaseService.db;
    final leads = await db.query('leads', where: 'blocked = 0');
    final templateResults = await db.query('templates');
    setState(() {
      allLeads = leads;
      templates = templateResults
          .map(
            (t) => MessageTemplate(
              id: t['id'] as int?,
              title: t['title'] as String,
              message: t['message'] as String,
            ),
          )
          .toList();
      loading = false;
    });
  }

  void _pastePhoneNumbers() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) {
      setState(() => _phoneController.text = data!.text!);
    }
  }

  void _selectTemplate(MessageTemplate t) {
    setState(() {
      selectedTemplate = t;
      _messageController.text = t.message;
    });
  }

  Future<void> _sendBulkSMS() async {
    final phones = <String>{};
    if (_phoneController.text.isNotEmpty) {
      phones.addAll(
        _phoneController.text
            .split('\n')
            .map((p) => p.trim())
            .where((p) => p.isNotEmpty),
      );
    }

    if (phones.isEmpty) {
      _showSnack('Please enter at least one phone number', Colors.red);
      return;
    }
    if (_messageController.text.isEmpty) {
      _showSnack('Please enter a message', Colors.red);
      return;
    }

    setState(() {
      sending = true;
      sentCount = 0;
      failedCount = 0;
    });

    for (final phone in phones) {
      try {
        if (selectedApp == 'whatsapp') {
          final ok = await WhatsAppService.sendWhatsApp(
            phone,
            _messageController.text,
          );
          setState(() => ok ? sentCount++ : failedCount++);
        } else {
          await SmsService.send(phone, _messageController.text);
          setState(() => sentCount++);
        }
        final db = await DatabaseService.db;
        await db.update(
          'leads',
          {'last_contacted': DateTime.now().millisecondsSinceEpoch},
          where: 'phone = ?',
          whereArgs: [phone],
        );
      } catch (_) {
        setState(() => failedCount++);
      }
      await Future.delayed(const Duration(milliseconds: 300));
    }

    setState(() => sending = false);
    _showResultDialog(phones.length);
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

  void _showResultDialog(int total) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        contentPadding: const EdgeInsets.fromLTRB(24, 20, 24, 0),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: sentCount == total
                    ? Colors.green.shade50
                    : Colors.orange.shade50,
                shape: BoxShape.circle,
              ),
              child: Icon(
                sentCount == total
                    ? Icons.check_circle_rounded
                    : Icons.warning_rounded,
                color: sentCount == total ? Colors.green : Colors.orange,
                size: 36,
              ),
            ),
            const SizedBox(height: 14),
            Text(
              sentCount == total ? 'All sent!' : 'Partially sent',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            _ResultRow(
              Icons.check_circle_rounded,
              'Sent',
              sentCount,
              Colors.green,
            ),
            _ResultRow(Icons.error_rounded, 'Failed', failedCount, Colors.red),
            _ResultRow(Icons.people_rounded, 'Total', total, _primary),
            const SizedBox(height: 16),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            style: TextButton.styleFrom(foregroundColor: _primary),
            child: const Text('Done'),
          ),
        ],
      ),
    );
  }

  String _cleanNumber(String phone) {
    phone = phone.replaceAll(RegExp(r'[^0-9+]'), '');
    if (phone.startsWith('+91'))
      phone = phone.substring(3);
    else if (phone.startsWith('91'))
      phone = phone.substring(2);
    return phone.replaceAll(RegExp(r'^0+'), '');
  }

  Future<void> _pickContacts() async {
    final status = await FlutterContacts.permissions.request(
      PermissionType.read,
    );
    if (status != PermissionStatus.granted) return;

    final contacts = await FlutterContacts.getAll(
      properties: {ContactProperty.name, ContactProperty.phone},
    );

    final selected = <Contact>{};
    final searchCtrl = TextEditingController();
    List<Contact> filtered = List.from(contacts);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          // ✅ Responsive height — respects keyboard and small screens
          height: (MediaQuery.of(context).size.height -
              MediaQuery.of(context).padding.top -
              MediaQuery.of(context).viewInsets.bottom) * 0.92,
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: Column(
            children: [
              // Handle
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(top: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),

              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Select contacts',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    if (selected.isNotEmpty)
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _primary.withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${selected.length} selected',
                          style: const TextStyle(
                            fontSize: 12,
                            color: _primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 12),

              // Search bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (q) {
                    setSheet(() {
                      filtered = contacts.where((c) {
                        final name = (c.displayName ?? '').toLowerCase();
                        final phone = c.phones.isNotEmpty
                            ? c.phones.first.number.toLowerCase()
                            : '';
                        return name.contains(q.toLowerCase()) ||
                            phone.contains(q.toLowerCase());
                      }).toList();
                    });
                  },
                  decoration: InputDecoration(
                    hintText: 'Search by name or number...',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    prefixIcon: Icon(
                      Icons.search_rounded,
                      color: Colors.grey.shade400,
                      size: 20,
                    ),
                    suffixIcon: searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: Icon(
                              Icons.close_rounded,
                              color: Colors.grey.shade400,
                              size: 18,
                            ),
                            onPressed: () {
                              searchCtrl.clear();
                              setSheet(() => filtered = List.from(contacts));
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 8),

              // Select all row
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(
                      '${filtered.length} contacts',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                    const Spacer(),
                    TextButton(
                      onPressed: () {
                        setSheet(() {
                          if (selected.length == filtered.length) {
                            selected.removeAll(filtered);
                          } else {
                            selected.addAll(filtered);
                          }
                        });
                      },
                      style: TextButton.styleFrom(
                        foregroundColor: _primary,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                      ),
                      child: Text(
                        selected.length == filtered.length
                            ? 'Deselect all'
                            : 'Select all',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              const Divider(height: 1),

              // Contact list
              Expanded(
                child: filtered.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.search_off_rounded,
                              size: 48,
                              color: Colors.grey.shade300,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              'No contacts found',
                              style: TextStyle(color: Colors.grey.shade500),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final c = filtered[i];
                          final isSelected = selected.contains(c);
                          final hasPhone = c.phones.isNotEmpty;
                          final initials =
                              (c.displayName ?? '?').trim().isNotEmpty
                              ? (c.displayName!).trim()[0].toUpperCase()
                              : '?';

                          return InkWell(
                            onTap: hasPhone
                                ? () {
                                    setSheet(() {
                                      if (isSelected)
                                        selected.remove(c);
                                      else
                                        selected.add(c);
                                    });
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 8, // ✅ reduced from 10 for small screens
                              ),
                              child: Row(
                                children: [
                                  // Avatar
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? _primary.withOpacity(0.15)
                                          : Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: isSelected
                                          ? const Icon(
                                              Icons.check_rounded,
                                              color: _primary,
                                              size: 20,
                                            )
                                          : Text(
                                              initials,
                                              style: TextStyle(
                                                fontSize: 16,
                                                fontWeight: FontWeight.w600,
                                                color: Colors.grey.shade600,
                                              ),
                                            ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          c.displayName ?? 'Unknown',
                                          style: TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w600,
                                            color: hasPhone
                                                ? const Color(0xFF1E293B)
                                                : Colors.grey.shade400,
                                          ),
                                        ),
                                        Text(
                                          hasPhone
                                              ? c.phones.first.number
                                              : 'No number',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: hasPhone
                                                ? Colors.grey.shade500
                                                : Colors.grey.shade300,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Checkbox
                                  Container(
                                    width: 22,
                                    height: 22,
                                    decoration: BoxDecoration(
                                      color: isSelected
                                          ? _primary
                                          : Colors.transparent,
                                      border: Border.all(
                                        color: isSelected
                                            ? _primary
                                            : Colors.grey.shade300,
                                        width: 1.5,
                                      ),
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: isSelected
                                        ? const Icon(
                                            Icons.check_rounded,
                                            color: Colors.white,
                                            size: 14,
                                          )
                                        : null,
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),

              // Add button
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () {
                            final numbers = selected
                                .where((c) => c.phones.isNotEmpty)
                                .map((c) => _cleanNumber(c.phones.first.number))
                                .where((n) => n.isNotEmpty)
                                .toSet();

                            setState(() {
                              final existing = _phoneController.text.trim();
                              final newNums = numbers.join('\n');
                              _phoneController.text = existing.isEmpty
                                  ? newNums
                                  : '$existing\n$newNums';
                            });
                            Navigator.pop(context);
                            _showSnack(
                              '${numbers.length} contacts added',
                              Colors.green,
                            );
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _primary,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: Colors.grey.shade200,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      selected.isEmpty
                          ? 'Select contacts to add'
                          : 'Add ${selected.length} contact${selected.length == 1 ? '' : 's'}',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Bulk SMS',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              'Send to multiple contacts at once',
              style: TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(44),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Row(
              children: [
                _AppChip(
                  label: 'SMS',
                  icon: Icons.message_rounded,
                  selected: selectedApp == 'sms',
                  color: Colors.green,
                  onTap: () => setState(() => selectedApp = 'sms'),
                ),
                const SizedBox(width: 10),
                _AppChip(
                  label: 'WhatsApp',
                  icon: Icons.chat_rounded,
                  selected: selectedApp == 'whatsapp',
                  color: const Color(0xFF25D366),
                  onTap: () => setState(() => selectedApp = 'whatsapp'),
                ),
              ],
            ),
          ),
        ),
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildTemplateSection(),
                  const SizedBox(height: 16),
                  _buildMessageSection(),
                  const SizedBox(height: 16),
                  _buildPhoneSection(),
                ],
              ),
            ),
      bottomNavigationBar: _buildSendButton(),
    );
  }

  // ── Template section ─────────────────────────────────────────────

  Widget _buildTemplateSection() {
    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.library_books_rounded,
            title: 'Choose template',
            color: _primary,
          ),
          const SizedBox(height: 12),
          templates.isEmpty
              ? Container(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  alignment: Alignment.center,
                  child: Text(
                    'No templates yet. Create one in Message Library.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500, fontSize: 13),
                  ),
                )
              : SizedBox(
                  height: 88,
                  child: ListView.builder(
                    scrollDirection: Axis.horizontal,
                    itemCount: templates.length,
                    itemBuilder: (context, i) {
                      final t = templates[i];
                      final sel = selectedTemplate?.id == t.id;
                      return GestureDetector(
                        onTap: () => _selectTemplate(t),
                        child: Container(
                          width: 160,
                          margin: const EdgeInsets.only(right: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: sel
                                ? _primary.withOpacity(0.08)
                                : Colors.grey.shade50,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                              color: sel ? _primary : Colors.grey.shade200,
                              width: sel ? 1.5 : 1,
                            ),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Icon(
                                    Icons.description_rounded,
                                    size: 14,
                                    color: sel
                                        ? _primary
                                        : Colors.grey.shade400,
                                  ),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      t.title,
                                      style: TextStyle(
                                        fontWeight: FontWeight.w600,
                                        fontSize: 12,
                                        color: sel
                                            ? _primary
                                            : const Color(0xFF1E293B),
                                      ),
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  if (sel)
                                    const Icon(
                                      Icons.check_circle_rounded,
                                      size: 14,
                                      color: _primary,
                                    ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                t.message,
                                style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.grey.shade500,
                                  height: 1.4,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
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

  // ── Message section ──────────────────────────────────────────────

  Widget _buildMessageSection() {
    final charCount = _messageController.text.length;
    final smsCount = (charCount / 160).ceil();

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SectionHeader(
            icon: Icons.edit_rounded,
            title: 'Message',
            color: _primary,
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _messageController,
            maxLines: 5,
            decoration: InputDecoration(
              hintText: 'Type your message here...',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                '$charCount characters',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500),
              ),
              const SizedBox(width: 8),
              if (charCount > 0)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: _primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$smsCount SMS part${smsCount > 1 ? 's' : ''}',
                    style: const TextStyle(
                      fontSize: 10,
                      color: _primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Phone section ────────────────────────────────────────────────

  Widget _buildPhoneSection() {
    final lineCount = _phoneController.text.isEmpty
        ? 0
        : _phoneController.text
              .split('\n')
              .where((l) => l.trim().isNotEmpty)
              .length;

    return _Card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(7),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(
                  Icons.phone_rounded,
                  color: _primary,
                  size: 16,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'Phone numbers',
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF1E293B),
                  ),
                ),
              ),
              // Contacts button
              _ActionChip(
                icon: Icons.contacts_rounded,
                label: 'Contacts',
                color: Colors.green,
                onTap: _pickContacts,
              ),
              const SizedBox(width: 8),
              // Paste button
              _ActionChip(
                icon: Icons.paste_rounded,
                label: 'Paste',
                color: _primary,
                onTap: _pastePhoneNumbers,
              ),
            ],
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _phoneController,
            maxLines: 6,
            decoration: InputDecoration(
              hintText: 'One number per line\n+919876543210\n+919876543211',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: const BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.all(14),
            ),
          ),
          if (lineCount > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.people_rounded, size: 14, color: _primary),
                const SizedBox(width: 6),
                Text(
                  '$lineCount recipient${lineCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _primary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const Spacer(),
                GestureDetector(
                  onTap: () => setState(() => _phoneController.clear()),
                  child: Text(
                    'Clear all',
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.red.shade400,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  // ── Send button ──────────────────────────────────────────────────

  Widget _buildSendButton() {
    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        12,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade100)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          onPressed: sending ? null : _sendBulkSMS,
          style: ElevatedButton.styleFrom(
            backgroundColor: _primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: Colors.grey.shade200,
            padding: const EdgeInsets.symmetric(vertical: 16),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            elevation: 0,
          ),
          child: sending
              ? const Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    ),
                    SizedBox(width: 12),
                    Text(
                      'Sending...',
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                )
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      selectedApp == 'whatsapp'
                          ? Icons.chat_rounded
                          : Icons.send_rounded,
                      size: 18,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      selectedApp == 'whatsapp'
                          ? 'Send via WhatsApp'
                          : 'Send bulk SMS',
                      style: const TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
        ),
      ),
    );
  }
}

// ── Reusable widgets ─────────────────────────────────────────────

class _Card extends StatelessWidget {
  final Widget child;
  const _Card({required this.child});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: child,
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final IconData icon;
  final String title;
  final Color color;
  const _SectionHeader({
    required this.icon,
    required this.title,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(7),
          decoration: BoxDecoration(
            color: color.withOpacity(0.1),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Icon(icon, color: color, size: 16),
        ),
        const SizedBox(width: 10),
        Text(
          title,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: Color(0xFF1E293B),
          ),
        ),
      ],
    );
  }
}

class _ActionChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;
  const _ActionChip({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: color.withOpacity(0.2)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 14, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: color,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _AppChip extends StatelessWidget {
  final String label;
  final IconData icon;
  final bool selected;
  final Color color;
  final VoidCallback onTap;
  const _AppChip({
    required this.label,
    required this.icon,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 7),
        decoration: BoxDecoration(
          color: selected
              ? Colors.white.withOpacity(0.25)
              : Colors.white.withOpacity(0.1),
          borderRadius: BorderRadius.circular(20),
          border: selected ? Border.all(color: Colors.white, width: 1.5) : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              label,
              style: TextStyle(
                color: Colors.white,
                fontSize: 13,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final int count;
  final Color color;
  const _ResultRow(this.icon, this.label, this.count, this.color);

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: 10),
          Text(label, style: const TextStyle(fontSize: 14)),
          const Spacer(),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
            decoration: BoxDecoration(
              color: color.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '$count',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: color,
                fontSize: 13,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
