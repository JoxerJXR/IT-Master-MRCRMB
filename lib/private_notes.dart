import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateNotesPage extends StatefulWidget {
  const PrivateNotesPage({super.key});

  @override
  State<PrivateNotesPage> createState() => _PrivateNotesPageState();
}

class _PrivateNotesPageState extends State<PrivateNotesPage> {
  static const storage = FlutterSecureStorage();
  static const notesKey = 'it_master_private_notes_v2';
  static const legacyKey = 'it_master_private_notes_v1';
  static const pinKey = 'it_master_notes_pin';

  final List<Map<String, String>> _notes = [];
  bool _loading = true;
  bool _unlocked = false;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final raw = await storage.read(key: notesKey);
      if (raw != null && raw.isNotEmpty) {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              _notes.add({
                'title': (item['title'] ?? 'Без названия').toString(),
                'body': (item['body'] ?? '').toString(),
              });
            }
          }
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось прочитать заметки: $e')),
        );
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<bool> _verifyPin() async {
    final savedPin = await storage.read(key: pinKey);
    if (savedPin == null || savedPin.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Сначала установите отдельный PIN заметок в настройках приложения.'),
          ),
        );
      }
      return false;
    }

    final controller = TextEditingController();
    final entered = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Защита личных заметок'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'PIN заметок',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('Разблокировать'),
          ),
        ],
      ),
    );
    controller.dispose();

    if (entered == null || !mounted) return false;
    if (entered != savedPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный PIN заметок')),
      );
      return false;
    }
    return true;
  }

  Future<void> _unlock() async {
    if (!await _verifyPin()) return;
    if (!mounted) return;

    // Migrate the previous single-text note without losing its contents.
    if (_notes.isEmpty) {
      final oldText = await storage.read(key: legacyKey);
      if (oldText != null && oldText.trim().isNotEmpty) {
        _notes.add({'title': 'Моя первая заметка', 'body': oldText});
        await _persist();
      }
    }
    if (mounted) setState(() => _unlocked = true);
  }

  Future<void> _persist() async {
    await storage.write(key: notesKey, value: jsonEncode(_notes));
  }

  Future<void> _editNote({int? index}) async {
    if (!_unlocked || _saving) return;
    final titleController = TextEditingController(
      text: index == null ? '' : _notes[index]['title'],
    );
    final bodyController = TextEditingController(
      text: index == null ? '' : _notes[index]['body'],
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(index == null ? 'Новая заметка' : 'Редактировать заметку'),
        content: SizedBox(
          width: 500,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: titleController,
                  autofocus: true,
                  maxLength: 80,
                  decoration: const InputDecoration(
                    labelText: 'Название заметки',
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: bodyController,
                  minLines: 6,
                  maxLines: 12,
                  decoration: const InputDecoration(
                    labelText: 'Текст заметки',
                    alignLabelWithHint: true,
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () {
              if (titleController.text.trim().isNotEmpty) {
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Сохранить'),
          ),
        ],
      ),
    );

    if (result == true && mounted) {
      final note = {
        'title': titleController.text.trim(),
        'body': bodyController.text,
      };
      setState(() {
        if (index == null) {
          _notes.insert(0, note);
        } else {
          _notes[index] = note;
        }
        _saving = true;
      });
      try {
        await _persist();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Заметка сохранена')),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Ошибка сохранения: $e')),
          );
        }
      } finally {
        if (mounted) setState(() => _saving = false);
      }
    }
    titleController.dispose();
    bodyController.dispose();
  }

  Future<void> _deleteNote(int index) async {
    if (!_unlocked || _saving) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Удалить заметку?'),
        content: Text('«${_notes[index]['title']}» будет удалена без возможности восстановления.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Отмена'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Удалить'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final removed = _notes.removeAt(index);
    setState(() => _saving = true);
    try {
      await _persist();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Заметка удалена')),
        );
      }
    } catch (e) {
      _notes.insert(index, removed);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Не удалось удалить заметку: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Личные заметки'),
        actions: [
          if (_unlocked)
            IconButton(
              tooltip: 'Заблокировать заметки',
              onPressed: () => setState(() => _unlocked = false),
              icon: const Icon(Icons.lock),
            ),
        ],
      ),
      floatingActionButton: _unlocked
          ? FloatingActionButton.extended(
              onPressed: _saving ? null : () => _editNote(),
              icon: const Icon(Icons.add),
              label: const Text('Новая заметка'),
            )
          : null,
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : !_unlocked
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.lock_outline,
                          size: 64,
                          color: Theme.of(context).colorScheme.primary,
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Заметки защищены PIN-кодом',
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 8),
                        const Text(
                          'Введите отдельный PIN заметок, чтобы просматривать, создавать, изменять или удалять записи.',
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 20),
                        FilledButton.icon(
                          onPressed: _unlock,
                          icon: const Icon(Icons.lock_open),
                          label: const Text('Разблокировать'),
                        ),
                      ],
                    ),
                  ),
                )
              : _notes.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.note_add_outlined, size: 56),
                            const SizedBox(height: 12),
                            const Text('Пока нет заметок'),
                            const SizedBox(height: 8),
                            const Text('Создайте отдельную заметку для паролей, Wi-Fi, оборудования или другой информации.',
                                textAlign: TextAlign.center),
                            const SizedBox(height: 16),
                            FilledButton.icon(
                              onPressed: () => _editNote(),
                              icon: const Icon(Icons.add),
                              label: const Text('Создать заметку'),
                            ),
                          ],
                        ),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 96),
                      children: [
                        const Card(
                          child: Padding(
                            padding: EdgeInsets.all(12),
                            child: Text(
                              'Заметки хранятся в защищённом хранилище Android на этом телефоне. Для любых действий с записями сначала требуется PIN заметок.',
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        for (var i = 0; i < _notes.length; i++)
                          Card(
                            child: ListTile(
                              leading: const Icon(Icons.note_alt_outlined),
                              title: Text(_notes[i]['title'] ?? 'Без названия'),
                              subtitle: Text(
                                (_notes[i]['body'] ?? '').replaceAll('\n', ' '),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              onTap: () => _editNote(index: i),
                              trailing: PopupMenuButton<String>(
                                onSelected: (action) {
                                  if (action == 'edit') _editNote(index: i);
                                  if (action == 'delete') _deleteNote(i);
                                },
                                itemBuilder: (_) => const [
                                  PopupMenuItem(value: 'edit', child: Text('Изменить')),
                                  PopupMenuItem(value: 'delete', child: Text('Удалить')),
                                ],
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }
}
