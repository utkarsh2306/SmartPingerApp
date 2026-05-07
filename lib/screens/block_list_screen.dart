import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:message_me/service/database_service.dart';

class BlockListScreen extends StatefulWidget {
  const BlockListScreen({super.key});

  @override
  State<BlockListScreen> createState() => _BlockListScreenState();
}

class BlockedNumber {
  final int? id;
  final String phone;
  final String? reason;
  final DateTime blockedAt;

  BlockedNumber({
    this.id,
    required this.phone,
    this.reason,
    DateTime? blockedAt,
  }) : blockedAt = blockedAt ?? DateTime.now();

  Map<String, dynamic> toMap() => {
    'id': id,
    'phone': phone,
    'reason': reason,
    'blocked_at': blockedAt.millisecondsSinceEpoch,
  };
}

class _BlockListScreenState extends State<BlockListScreen> {
  List<BlockedNumber> blockedNumbers = [];
  bool loading = true;
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _reasonController = TextEditingController();

  static const _primary = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    loadBlockedNumbers();
    _requestPermissions();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _reasonController.dispose();
    super.dispose();
  }

  Future<void> _requestPermissions() async {
    await FlutterContacts.permissions.request(PermissionType.read);
  }

  Future<void> loadBlockedNumbers() async {
    setState(() => loading = true);
    final db = await DatabaseService.db;
    final results = await db.query(
      'blocked_numbers',
      orderBy: 'blocked_at DESC',
    );
    setState(() {
      blockedNumbers = results
          .map(
            (r) => BlockedNumber(
              id: r['id'] as int,
              phone: r['phone'] as String,
              reason: r['reason'] as String?,
              blockedAt: DateTime.fromMillisecondsSinceEpoch(
                r['blocked_at'] as int,
              ),
            ),
          )
          .toList();
      loading = false;
    });
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

  Future<void> _pastePhone() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    if (data?.text != null) setState(() => _phoneController.text = data!.text!);
  }

  Future<void> _pickContact() async {
    try {
      final status = await FlutterContacts.permissions.request(
        PermissionType.read,
      );
      if (status != PermissionStatus.granted) return;
      final contactId = await FlutterContacts.native.showPicker();
      if (contactId == null) return;
      final contact = await FlutterContacts.get(
        contactId,
        properties: ContactProperties.all,
      );
      if (contact == null || contact.phones.isEmpty) return;
      String phone = contact.phones.first.number.replaceAll(
        RegExp(r'[^0-9+]'),
        '',
      );
      if (phone.startsWith('+91'))
        phone = phone.substring(3);
      else if (phone.startsWith('91'))
        phone = phone.substring(2);
      phone = phone.replaceAll(RegExp(r'^0+'), '');
      setState(() => _phoneController.text = phone);
    } catch (e) {
      debugPrint('Contact pick error: $e');
    }
  }

  Future<void> _blockSingleNumber() async {
    if (_phoneController.text.trim().isEmpty) {
      _showSnack('Please enter a phone number', Colors.red);
      return;
    }
    final phone = _phoneController.text.trim();
    if (blockedNumbers.any((b) => b.phone == phone)) {
      _showSnack('This number is already blocked', Colors.orange);
      return;
    }
    await _blockNumber(
      phone,
      _reasonController.text.isNotEmpty ? _reasonController.text : null,
    );
    _phoneController.clear();
    _reasonController.clear();
    _showSnack('Number blocked', Colors.green);
  }

  Future<void> _blockNumber(String phone, String? reason) async {
    final db = await DatabaseService.db;
    await db.insert(
      'blocked_numbers',
      BlockedNumber(phone: phone, reason: reason).toMap(),
    );
    await db.update(
      'leads',
      {'blocked': 1},
      where: 'phone = ?',
      whereArgs: [phone],
    );
    await loadBlockedNumbers();
  }

  Future<void> _unblockNumber(int id, String phone) async {
    final confirmed = await _showConfirmSheet(
      title: 'Unblock number?',
      subtitle: phone,
      confirmLabel: 'Unblock',
      confirmColor: Colors.green,
      icon: Icons.lock_open_rounded,
      iconColor: Colors.green,
    );
    if (confirmed != true) return;
    final db = await DatabaseService.db;
    await db.delete('blocked_numbers', where: 'id = ?', whereArgs: [id]);
    await db.update(
      'leads',
      {'blocked': 0},
      where: 'phone = ?',
      whereArgs: [phone],
    );
    await loadBlockedNumbers();
    _showSnack('Number unblocked', Colors.green);
  }

  Future<void> _unblockAll() async {
    if (blockedNumbers.isEmpty) return;
    final confirmed = await _showConfirmSheet(
      title: 'Unblock all numbers?',
      subtitle: '${blockedNumbers.length} numbers will be unblocked',
      confirmLabel: 'Unblock all',
      confirmColor: Colors.red,
      icon: Icons.delete_sweep_rounded,
      iconColor: Colors.red,
    );
    if (confirmed != true) return;
    final db = await DatabaseService.db;
    for (final b in blockedNumbers) {
      await db.delete('blocked_numbers', where: 'id = ?', whereArgs: [b.id]);
      await db.update(
        'leads',
        {'blocked': 0},
        where: 'phone = ?',
        whereArgs: [b.phone],
      );
    }
    await loadBlockedNumbers();
    _showSnack('All numbers unblocked', Colors.green);
  }

  Future<bool?> _showConfirmSheet({
    required String title,
    required String subtitle,
    required String confirmLabel,
    required Color confirmColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return showModalBottomSheet<bool>(
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
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: iconColor.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 28),
            ),
            const SizedBox(height: 14),
            Text(
              title,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 6),
            Text(
              subtitle,
              style: TextStyle(fontSize: 13, color: Colors.grey.shade600),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: () => Navigator.pop(context, false),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 14),
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
                      backgroundColor: confirmColor,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      confirmLabel,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Multi-contact picker ─────────────────────────────────────────
  Future<void> _pickMultipleContacts() async {
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

    final reasonCtrl = TextEditingController();

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (context, setSheet) => Container(
          height: MediaQuery.of(context).size.height * 0.88,
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
                        'Select contacts to block',
                        style: TextStyle(
                          fontSize: 17,
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

              // Search
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: searchCtrl,
                  onChanged: (q) => setSheet(() {
                    filtered = contacts.where((c) {
                      final name = (c.displayName ?? '').toLowerCase();
                      final phone = c.phones.isNotEmpty
                          ? c.phones.first.number.toLowerCase()
                          : '';
                      return name.contains(q.toLowerCase()) ||
                          phone.contains(q.toLowerCase());
                    }).toList();
                  }),
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

              // Count + select all
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
                      onPressed: () => setSheet(() {
                        if (selected.length == filtered.length) {
                          selected.removeAll(filtered);
                        } else {
                          selected.addAll(
                            filtered.where((c) => c.phones.isNotEmpty),
                          );
                        }
                      }),
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
                          final isSel = selected.contains(c);
                          final hasPhone = c.phones.isNotEmpty;
                          final initials =
                              (c.displayName ?? '?').trim().isNotEmpty
                              ? c.displayName![0].toUpperCase()
                              : '?';
                          final alreadyBlocked = blockedNumbers.any(
                            (b) =>
                                hasPhone &&
                                b.phone == _cleanNumber(c.phones.first.number),
                          );

                          return InkWell(
                            onTap: (hasPhone && !alreadyBlocked)
                                ? () {
                                    setSheet(() {
                                      if (isSel)
                                        selected.remove(c);
                                      else
                                        selected.add(c);
                                    });
                                  }
                                : null,
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 10,
                              ),
                              child: Row(
                                children: [
                                  // Avatar
                                  Container(
                                    width: 42,
                                    height: 42,
                                    decoration: BoxDecoration(
                                      color: alreadyBlocked
                                          ? Colors.grey.shade100
                                          : isSel
                                          ? _primary.withOpacity(0.12)
                                          : Colors.grey.shade100,
                                      shape: BoxShape.circle,
                                    ),
                                    child: Center(
                                      child: isSel
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
                                                color: alreadyBlocked
                                                    ? Colors.grey.shade300
                                                    : Colors.grey.shade600,
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
                                            color: alreadyBlocked
                                                ? Colors.grey.shade400
                                                : const Color(0xFF1E293B),
                                          ),
                                        ),
                                        Row(
                                          children: [
                                            Text(
                                              hasPhone
                                                  ? c.phones.first.number
                                                  : 'No number',
                                              style: TextStyle(
                                                fontSize: 12,
                                                color: Colors.grey.shade500,
                                              ),
                                            ),
                                            if (alreadyBlocked) ...[
                                              const SizedBox(width: 6),
                                              Container(
                                                padding:
                                                    const EdgeInsets.symmetric(
                                                      horizontal: 6,
                                                      vertical: 1,
                                                    ),
                                                decoration: BoxDecoration(
                                                  color: _primary.withOpacity(
                                                    0.1,
                                                  ),
                                                  borderRadius:
                                                      BorderRadius.circular(4),
                                                ),
                                                child: const Text(
                                                  'Blocked',
                                                  style: TextStyle(
                                                    fontSize: 10,
                                                    color: _primary,
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  // Checkbox
                                  if (!alreadyBlocked)
                                    Container(
                                      width: 22,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: isSel
                                            ? _primary
                                            : Colors.transparent,
                                        border: Border.all(
                                          color: isSel
                                              ? _primary
                                              : Colors.grey.shade300,
                                          width: 1.5,
                                        ),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: isSel
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

              // Reason + block button
              Container(
                padding: EdgeInsets.fromLTRB(
                  16,
                  12,
                  16,
                  MediaQuery.of(context).viewInsets.bottom + 20,
                ),
                decoration: BoxDecoration(
                  color: Colors.white,
                  border: Border(top: BorderSide(color: Colors.grey.shade100)),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    TextField(
                      controller: reasonCtrl,
                      decoration: InputDecoration(
                        hintText: 'Reason for blocking (optional)',
                        hintStyle: TextStyle(
                          color: Colors.grey.shade400,
                          fontSize: 13,
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade100,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 10,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: selected.isEmpty
                            ? null
                            : () async {
                                Navigator.pop(context);
                                int count = 0;
                                for (final c in selected) {
                                  if (c.phones.isEmpty) continue;
                                  final phone = _cleanNumber(
                                    c.phones.first.number,
                                  );
                                  if (phone.isEmpty) continue;
                                  if (blockedNumbers.any(
                                    (b) => b.phone == phone,
                                  ))
                                    continue;
                                  await _blockNumber(
                                    phone,
                                    reasonCtrl.text.isNotEmpty
                                        ? reasonCtrl.text
                                        : null,
                                  );
                                  count++;
                                }
                                _showSnack(
                                  '$count number${count == 1 ? '' : 's'} blocked',
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
                          elevation: 0,
                        ),
                        child: Text(
                          selected.isEmpty
                              ? 'Select contacts to block'
                              : 'Block ${selected.length} contact${selected.length == 1 ? '' : 's'}',
                          style: const TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
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

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inDays == 0)
      return 'Today ${date.hour.toString().padLeft(2, '0')}:${date.minute.toString().padLeft(2, '0')}';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      appBar: AppBar(
        backgroundColor: _primary,
        foregroundColor: Colors.white,
        elevation: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Block list',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            Text(
              '${blockedNumbers.length} blocked number${blockedNumbers.length == 1 ? '' : 's'}',
              style: const TextStyle(
                fontSize: 11,
                color: Colors.white70,
                fontWeight: FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (blockedNumbers.isNotEmpty)
            IconButton(
              onPressed: _unblockAll,
              icon: const Icon(Icons.delete_sweep_rounded),
              tooltip: 'Unblock all',
            ),
        ],
      ),
      body: loading
          ? const Center(child: CircularProgressIndicator(color: _primary))
          : Column(
              children: [
                _buildAddCard(),
                Expanded(
                  child: blockedNumbers.isEmpty
                      ? _buildEmpty()
                      : ListView.builder(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                          itemCount: blockedNumbers.length,
                          itemBuilder: (_, i) =>
                              _buildBlockedCard(blockedNumbers[i]),
                        ),
                ),
              ],
            ),
    );
  }

  // ── Add card ─────────────────────────────────────────────────────

  Widget _buildAddCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: _primary,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              const Text(
                'Block a number',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: Color(0xFF1E293B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Phone row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    hintText: 'Phone number',
                    hintStyle: TextStyle(
                      color: Colors.grey.shade400,
                      fontSize: 14,
                    ),
                    prefixText: '+91 ',
                    filled: true,
                    fillColor: Colors.grey.shade50,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: _primary, width: 1.5),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 12,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              _IconBtn(
                icon: Icons.paste_rounded,
                color: _primary,
                onTap: _pastePhone,
                tooltip: 'Paste',
              ),
              const SizedBox(width: 6),
              _IconBtn(
                icon: Icons.person_rounded,
                color: _primary,
                onTap: _pickContact,
                tooltip: 'Pick contact',
              ),
              const SizedBox(width: 6),
              _IconBtn(
                icon: Icons.people_rounded,
                color: _primary,
                onTap: _pickMultipleContacts,
                tooltip: 'Select multiple',
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Reason
          TextField(
            controller: _reasonController,
            decoration: InputDecoration(
              hintText: 'Reason (optional)',
              hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 14),
              filled: true,
              fillColor: Colors.grey.shade50,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: _primary, width: 1.5),
              ),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 14,
                vertical: 12,
              ),
            ),
          ),
          const SizedBox(height: 14),

          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _blockSingleNumber,
              style: ElevatedButton.styleFrom(
                backgroundColor: _primary,
                foregroundColor: Colors.white,
                elevation: 0,
                padding: const EdgeInsets.symmetric(vertical: 13),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: const Text(
                'Block number',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Empty state ──────────────────────────────────────────────────

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              padding: const EdgeInsets.all(28),
              decoration: BoxDecoration(
                color: _primary.withOpacity(0.08),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.block_rounded, size: 52, color: _primary),
            ),
            const SizedBox(height: 20),
            const Text(
              'No blocked numbers',
              style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 10),
            Text(
              'Numbers you block will not receive any automated SMS from your campaigns.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 13,
                color: Colors.grey.shade600,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Blocked number card ──────────────────────────────────────────

  Widget _buildBlockedCard(BlockedNumber b) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: InkWell(
        onLongPress: () => _unblockNumber(b.id!, b.phone),
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _primary.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.block_rounded,
                  color: _primary,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      b.phone,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                        color: Color(0xFF1E293B),
                      ),
                    ),
                    if (b.reason != null) ...[
                      const SizedBox(height: 3),
                      Text(
                        b.reason!,
                        style: TextStyle(
                          fontSize: 12,
                          color: Colors.grey.shade500,
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(
                          Icons.access_time_rounded,
                          size: 11,
                          color: Colors.grey.shade400,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _formatDate(b.blockedAt),
                          style: TextStyle(
                            fontSize: 11,
                            color: Colors.grey.shade400,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => _unblockNumber(b.id!, b.phone),
                icon: const Icon(
                  Icons.lock_open_rounded,
                  color: _primary,
                  size: 20,
                ),
                tooltip: 'Unblock',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Helper widget ────────────────────────────────────────────────

class _IconBtn extends StatelessWidget {
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  const _IconBtn({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: color.withOpacity(0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withOpacity(0.2)),
          ),
          child: Icon(icon, color: color, size: 18),
        ),
      ),
    );
  }
}
