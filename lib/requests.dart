import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'cartridges.dart';

const requestStatuses = ['Новая', 'В работе', 'Ожидает', 'Выполнена', 'Отменена'];
const requestPriorities = ['Низкий', 'Обычный', 'Высокий', 'Срочный'];

class RequestsPage extends StatefulWidget {
  const RequestsPage({super.key});
  @override
  State<RequestsPage> createState() => _RequestsPageState();
}

class _RequestsPageState extends State<RequestsPage> {
  List<Map<String, Object?>> rows = [];
  bool loading = true;
  String filter = 'Все';
  String search = '';
  final searchController = TextEditingController();

  Future<void> _prepare() async {
    final db = await CartridgeDatabase.instance.database;
    await db.execute('''CREATE TABLE IF NOT EXISTS service_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT, created_at TEXT NOT NULL, updated_at TEXT NOT NULL,
      department TEXT NOT NULL DEFAULT '', requester TEXT NOT NULL DEFAULT '',
      room TEXT NOT NULL DEFAULT '', category TEXT NOT NULL DEFAULT 'Другое',
      equipment TEXT NOT NULL DEFAULT '', inventory_number TEXT NOT NULL DEFAULT '',
      description TEXT NOT NULL, priority TEXT NOT NULL DEFAULT 'Обычный',
      executor TEXT NOT NULL DEFAULT '', status TEXT NOT NULL DEFAULT 'Новая',
      resolution TEXT NOT NULL DEFAULT '')''');
    await db.execute('''CREATE TABLE IF NOT EXISTS request_history (
      id INTEGER PRIMARY KEY AUTOINCREMENT, request_id INTEGER NOT NULL,
      date TEXT NOT NULL, action TEXT NOT NULL, details TEXT NOT NULL DEFAULT '')''');
  }

  @override
  void initState() { super.initState(); _load(); }
  @override
  void dispose() { searchController.dispose(); super.dispose(); }

  Future<void> _load() async {
    await _prepare();
    final data = await (await CartridgeDatabase.instance.database).query('service_requests', orderBy: 'id DESC');
    if (mounted) setState(() { rows = data; loading = false; });
  }

  Future<void> _create() async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => const RequestFormPage()));
    if (result == true) _load();
  }

  Future<void> _open(Map<String, Object?> row) async {
    final result = await Navigator.push<bool>(context, MaterialPageRoute(builder: (_) => RequestDetailsPage(request: row)));
    if (result == true) _load();
  }

  @override
  Widget build(BuildContext context) {
    final visible = rows.where((r) {
      if (filter != 'Все' && r['status'] != filter) return false;
      final q = search.trim().toLowerCase();
      if (q.isEmpty) return true;
      final text = ['id','department','requester','room','category','equipment','inventory_number','description','executor']
          .map((k) => (r[k] ?? '').toString().toLowerCase()).join(' ');
      return text.contains(q);
    }).toList();
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(onPressed: _create, icon: const Icon(Icons.add), label: const Text('Новая заявка')),
      body: loading ? const Center(child: CircularProgressIndicator()) : RefreshIndicator(
        onRefresh: _load,
        child: ListView(padding: const EdgeInsets.fromLTRB(16, 12, 16, 90), children: [
          Row(children: [
            Expanded(child: _RequestCount(title: 'Всего', count: rows.length, icon: Icons.assignment_outlined)),
            const SizedBox(width: 8),
            Expanded(child: _RequestCount(title: 'Новые', count: rows.where((r) => r['status'] == 'Новая').length, icon: Icons.fiber_new)),
            const SizedBox(width: 8),
            Expanded(child: _RequestCount(title: 'В работе', count: rows.where((r) => r['status'] == 'В работе').length, icon: Icons.build_outlined)),
          ]),
          const SizedBox(height: 14),
          TextField(controller: searchController, onChanged: (v) => setState(() => search = v),
            decoration: InputDecoration(prefixIcon: const Icon(Icons.search), hintText: 'Поиск по заявкам',
              border: const OutlineInputBorder(), suffixIcon: search.isEmpty ? null : IconButton(icon: const Icon(Icons.clear), onPressed: () { searchController.clear(); setState(() => search = ''); }))),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(value: filter, decoration: const InputDecoration(labelText: 'Статус', border: OutlineInputBorder(), isDense: true),
            items: ['Все', ...requestStatuses].map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
            onChanged: (v) => setState(() => filter = v ?? 'Все')),
          const SizedBox(height: 12),
          if (visible.isEmpty)
            Padding(padding: const EdgeInsets.all(28), child: Text(rows.isEmpty ? 'Заявок пока нет. Нажмите «Новая заявка», чтобы зарегистрировать неисправность.' : 'Заявки не найдены.', textAlign: TextAlign.center))
          else
            ...visible.map((r) => _RequestTile(request: r, onTap: () => _open(r))),
        ]),
      ),
    );
  }
}

class _RequestCount extends StatelessWidget {
  final String title; final int count; final IconData icon;
  const _RequestCount({required this.title, required this.count, required this.icon});
  @override
  Widget build(BuildContext context) => Card(elevation: 0, child: Padding(padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 5),
    child: Column(children: [Icon(icon, color: Theme.of(context).colorScheme.primary), const SizedBox(height: 5),
      Text('$count', style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
      Text(title, style: Theme.of(context).textTheme.bodySmall)])));
}

class _RequestTile extends StatelessWidget {
  final Map<String, Object?> request; final VoidCallback onTap;
  const _RequestTile({required this.request, required this.onTap});
  @override
  Widget build(BuildContext context) => Card(elevation: 0, margin: const EdgeInsets.only(bottom: 9), child: ListTile(
    onTap: onTap, leading: CircleAvatar(child: Text('#${request['id']}', style: const TextStyle(fontSize: 11))),
    title: Text(request['description'] as String, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.w600)),
    subtitle: Text('${request['department']} · ${request['category']}\n${_requestDate(request['created_at'] as String)} · ${request['status']} · ${request['priority']}'),
    trailing: const Icon(Icons.chevron_right), isThreeLine: true));
}

class RequestFormPage extends StatefulWidget {
  const RequestFormPage({super.key});
  @override
  State<RequestFormPage> createState() => _RequestFormPageState();
}

class _RequestFormPageState extends State<RequestFormPage> {
  final keyForm = GlobalKey<FormState>();
  final department = TextEditingController(), requester = TextEditingController(), room = TextEditingController();
  final equipment = TextEditingController(), inventory = TextEditingController(), description = TextEditingController(), executor = TextEditingController();
  String category = 'Компьютер', priority = 'Обычный';
  DateTime createdAt = DateTime.now();
  bool saving = false;

  @override
  void dispose() { for (final c in [department, requester, room, equipment, inventory, description, executor]) { c.dispose(); } super.dispose(); }

  Widget _field(TextEditingController c, String label, {bool required = false, int lines = 1}) => Padding(
    padding: const EdgeInsets.only(bottom: 11),
    child: TextFormField(controller: c, maxLines: lines, decoration: InputDecoration(labelText: label, border: const OutlineInputBorder()),
      validator: required ? (v) => v == null || v.trim().isEmpty ? 'Заполните поле' : null : null));

  Future<void> _save() async {
    if (!keyForm.currentState!.validate()) return;
    setState(() => saving = true);
    try {
      final db = await CartridgeDatabase.instance.database;
      final now = DateTime.now().toIso8601String();
      final id = await db.insert('service_requests', {
        'created_at': createdAt.toIso8601String(), 'updated_at': now,
        'department': department.text.trim(), 'requester': requester.text.trim(), 'room': room.text.trim(),
        'category': category, 'equipment': equipment.text.trim(), 'inventory_number': inventory.text.trim(),
        'description': description.text.trim(), 'priority': priority, 'executor': executor.text.trim(),
        'status': 'Новая', 'resolution': '',
      });
      await db.insert('request_history', {'request_id': id, 'date': now, 'action': 'Заявка создана', 'details': 'Первичная регистрация'});
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Ошибка сохранения: $e')));
    } finally { if (mounted) setState(() => saving = false); }
  }

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: const Text('Новая заявка')),
    body: Form(key: keyForm, child: ListView(padding: const EdgeInsets.all(16), children: [
      OutlinedButton.icon(onPressed: () async {
        final d = await showDatePicker(context: context, initialDate: createdAt, firstDate: DateTime(2020), lastDate: DateTime(2100));
        if (d != null && mounted) setState(() => createdAt = DateTime(d.year, d.month, d.day, createdAt.hour, createdAt.minute));
      }, icon: const Icon(Icons.calendar_month), label: Text('Дата: ${DateFormat('dd.MM.yyyy HH:mm').format(createdAt)}')),
      const SizedBox(height: 12),
      Text('Заявитель', style: Theme.of(context).textTheme.titleMedium),
      _field(department, 'Отделение', required: true), _field(requester, 'ФИО заявителя'), _field(room, 'Номер кабинета'),
      const Divider(height: 24),
      Text('Неисправность', style: Theme.of(context).textTheme.titleMedium),
      DropdownButtonFormField<String>(value: category, decoration: const InputDecoration(labelText: 'Тип проблемы', border: OutlineInputBorder()),
        items: ['Компьютер','Принтер / МФУ','Сеть / Интернет','Телефон','Программное обеспечение','Монитор','Другое'].map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(),
        onChanged: (v) => setState(() => category = v ?? 'Другое')),
      const SizedBox(height: 11),
      _field(equipment, 'Модель / название оборудования'), _field(inventory, 'Инвентарный номер'),
      _field(description, 'Подробное описание неисправности', required: true, lines: 4),
      DropdownButtonFormField<String>(value: priority, decoration: const InputDecoration(labelText: 'Приоритет', border: OutlineInputBorder()),
        items: requestPriorities.map((v) => DropdownMenuItem(value: v, child: Text(v))).toList(), onChanged: (v) => setState(() => priority = v ?? 'Обычный')),
      const SizedBox(height: 14),
      Text('Исполнение', style: Theme.of(context).textTheme.titleMedium),
      _field(executor, 'Исполнитель (можно заполнить позже)'),
      const SizedBox(height: 8),
      FilledButton.icon(onPressed: saving ? null : _save, icon: saving ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.save),
        label: Text(saving ? 'Сохранение...' : 'Зарегистрировать заявку')),
    ])));
}

class RequestDetailsPage extends StatefulWidget {
  final Map<String, Object?> request;
  const RequestDetailsPage({super.key, required this.request});
  @override
  State<RequestDetailsPage> createState() => _RequestDetailsPageState();
}

class _RequestDetailsPageState extends State<RequestDetailsPage> {
  late Map<String, Object?> request;
  List<Map<String, Object?>> history = [];
  final comment = TextEditingController(), resolution = TextEditingController(), executor = TextEditingController();
  bool loading = true;
  int get id => request['id'] as int;

  @override
  void initState() { super.initState(); request = Map<String, Object?>.from(widget.request); executor.text = request['executor'] as String? ?? ''; _load(); }
  @override
  void dispose() { comment.dispose(); resolution.dispose(); executor.dispose(); super.dispose(); }

  Future<void> _load() async {
    final db = await CartridgeDatabase.instance.database;
    final data = await db.query('request_history', where: 'request_id=?', whereArgs: [id], orderBy: 'id DESC');
    if (mounted) setState(() { history = data; loading = false; });
  }

  Future<void> _change(String field, String value, String action) async {
    final old = (request[field] ?? '').toString();
    if (old == value) return;
    final now = DateTime.now().toIso8601String();
    final db = await CartridgeDatabase.instance.database;
    await db.update('service_requests', {field: value, 'updated_at': now}, where: 'id=?', whereArgs: [id]);
    await db.insert('request_history', {'request_id': id, 'date': now, 'action': action, 'details': '$old → $value'});
    if (!mounted) return;
    setState(() { request[field] = value; request['updated_at'] = now; });
    await _load();
  }

  Future<void> _comment() async {
    final value = comment.text.trim(); if (value.isEmpty) return;
    await (await CartridgeDatabase.instance.database).insert('request_history', {
      'request_id': id, 'date': DateTime.now().toIso8601String(), 'action': 'Комментарий', 'details': value});
    comment.clear(); await _load();
  }

  Future<void> _resolution() async {
    final value = resolution.text.trim(); if (value.isEmpty) return;
    await _change('resolution', value, 'Результат работ изменён'); resolution.clear();
  }

  Widget _info(String label, Object? value) => Padding(padding: const EdgeInsets.only(top: 7), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
    SizedBox(width: 118, child: Text('$label:', style: const TextStyle(fontWeight: FontWeight.w600))),
    Expanded(child: Text(value?.toString().isNotEmpty == true ? value.toString() : '—'))]));

  @override
  Widget build(BuildContext context) => Scaffold(appBar: AppBar(title: Text('Заявка #$id')),
    body: loading ? const Center(child: CircularProgressIndicator()) : ListView(padding: const EdgeInsets.all(16), children: [
      Card(elevation: 0, child: Padding(padding: const EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(request['description'] as String, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
        _info('Создана', _requestDate(request['created_at'] as String)), _info('Отделение', request['department']),
        _info('Заявитель', request['requester']), _info('Кабинет', request['room']), _info('Тип', request['category']),
        _info('Оборудование', request['equipment']), _info('Инв. номер', request['inventory_number']),
        _info('Приоритет', request['priority']), _info('Исполнитель', request['executor']),
        _info('Статус', request['status']), if ((request['resolution'] ?? '').toString().isNotEmpty) _info('Результат', request['resolution']),
      ]))),
      const SizedBox(height: 14),
      Text('Статус заявки', style: Theme.of(context).textTheme.titleMedium),
      DropdownButtonFormField<String>(value: requestStatuses.contains(request['status']) ? request['status'] as String : 'Новая',
        decoration: const InputDecoration(border: OutlineInputBorder()), items: requestStatuses.map((s) => DropdownMenuItem(value: s, child: Text(s))).toList(),
        onChanged: (v) { if (v != null) _change('status', v, 'Статус изменён'); }),
      const SizedBox(height: 14),
      Text('Исполнитель', style: Theme.of(context).textTheme.titleMedium),
      TextField(controller: executor, textInputAction: TextInputAction.done, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'ФИО исполнителя')),
      Align(alignment: Alignment.centerRight, child: FilledButton.tonal(onPressed: () => _change('executor', executor.text.trim(), 'Исполнитель изменён'), child: const Text('Сохранить исполнителя'))),
      const SizedBox(height: 8),
      Text('Результат выполненных работ', style: Theme.of(context).textTheme.titleMedium),
      TextField(controller: resolution, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Что было сделано')),
      Align(alignment: Alignment.centerRight, child: TextButton.icon(onPressed: _resolution, icon: const Icon(Icons.save_outlined), label: const Text('Сохранить результат'))),
      const Divider(height: 28),
      Text('Комментарий / ход работ', style: Theme.of(context).textTheme.titleMedium),
      TextField(controller: comment, maxLines: 2, decoration: const InputDecoration(border: OutlineInputBorder(), hintText: 'Добавить запись в журнал')),
      Align(alignment: Alignment.centerRight, child: FilledButton.icon(onPressed: _comment, icon: const Icon(Icons.add_comment), label: const Text('Добавить'))),
      const Divider(height: 28),
      Text('История заявки', style: Theme.of(context).textTheme.titleMedium),
      if (history.isEmpty) const Text('История пока пуста.'),
      ...history.map((h) => ListTile(contentPadding: EdgeInsets.zero, leading: const Icon(Icons.history),
        title: Text(h['action'] as String), subtitle: Text('${_requestDate(h['date'] as String)}\n${h['details']}'))),
    ]));
}

String _requestDate(String value) {
  try { return DateFormat('dd.MM.yyyy HH:mm').format(DateTime.parse(value).toLocal()); }
  catch (_) { return value; }
}
