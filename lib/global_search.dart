import 'package:flutter/material.dart';
import 'cartridges.dart';
import 'equipment.dart';
import 'requests.dart';
import 'revision.dart';

class GlobalSearchPage extends StatefulWidget {
  const GlobalSearchPage({super.key});
  @override
  State<GlobalSearchPage> createState() => _GlobalSearchPageState();
}

class _GlobalSearchPageState extends State<GlobalSearchPage> {
  final controller = TextEditingController();
  List<Map<String, Object?>> results = [];
  bool searching = false;
  int _searchToken = 0;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  Future<void> search(String value) async {
    final token = ++_searchToken;
    final q = value.trim();
    if (q.isEmpty) {
      setState(() { results = []; searching = false; });
      return;
    }
    setState(() => searching = true);
    final db = await CartridgeDatabase.instance.database;
    final tables = await db.rawQuery("SELECT name FROM sqlite_master WHERE type='table'");
    final existing = tables.map((r) => r['name'] as String).toSet();
    final found = <Map<String, Object?>>[];

    Future<void> scan(String table, String label, List<String> columns,
        String titleColumn, String subtitleColumn) async {
      if (!existing.contains(table)) return;
      final info = await db.rawQuery('PRAGMA table_info($table)');
      final available = info.map((r) => r['name'] as String).toSet();
      final valid = columns.where(available.contains).toList();
      if (valid.isEmpty || !available.contains(titleColumn)) return;
      final where = valid.map((c) => 'CAST($c AS TEXT) LIKE ?').join(' OR ');
      final rows = await db.query(table, where: where,
          whereArgs: List.filled(valid.length, '%$q%'), limit: 30);
      for (final row in rows) {
        found.add({
          'table': table,
          'section': label,
          'title': (row[titleColumn] ?? label).toString(),
          'subtitle': available.contains(subtitleColumn)
              ? (row[subtitleColumn] ?? '').toString() : '',
          'id': row['id'],
          'row': row,
        });
      }
    }

    try {
      await scan('cartridges', 'Картриджи',
          ['code', 'model', 'printer_model', 'department', 'sender_name', 'status'],
          'model', 'status');
      await scan('it_equipment', 'Оборудование',
          ['title', 'category', 'model', 'inventory_number', 'serial_number', 'location', 'status'],
          'title', 'location');
      await scan('service_requests', 'Заявки',
          ['description', 'department', 'requester', 'room', 'equipment', 'inventory_number', 'executor', 'status'],
          'description', 'status');
      await scan('revision_employees', 'Сотрудники',
          ['full_name', 'department', 'position'], 'full_name', 'department');
      await scan('revision_assets', 'Имущество',
          ['title', 'category', 'model', 'inventory_number', 'serial_number', 'note'],
          'title', 'inventory_number');
      await scan('it_consumables', 'Расходники',
          ['name', 'category', 'location', 'note'], 'name', 'location');
    } catch (e) {
      if (mounted && token == _searchToken) {
        setState(() { results = []; searching = false; });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Ошибка поиска: $e')),
        );
      }
      return;
    }
    if (mounted && token == _searchToken) {
      setState(() { results = found; searching = false; });
    }
  }

  Future<void> _openResult(Map<String, Object?> result) async {
    final table = result['table'] as String;
    final row = Map<String, Object?>.from(result['row'] as Map);
    Widget? page;
    switch (table) {
      case 'cartridges':
        page = CartridgeDetailsPage(cartridge: row);
        break;
      case 'it_equipment':
        page = EquipmentEditPage(item: row);
        break;
      case 'service_requests':
        page = RequestDetailsPage(request: row);
        break;
      case 'revision_employees':
        page = RevisionEmployeePage(employee: row);
        break;
      case 'revision_assets':
      case 'it_consumables':
        await showDialog<void>(
          context: context,
          builder: (c) => AlertDialog(
            title: Text(result['title'] as String),
            content: Text([
              if ((row['category'] ?? '').toString().isNotEmpty) 'Категория: ${row['category']}',
              if ((row['model'] ?? '').toString().isNotEmpty) 'Модель: ${row['model']}',
              if ((row['inventory_number'] ?? '').toString().isNotEmpty) 'Инвентарный номер: ${row['inventory_number']}',
              if ((row['serial_number'] ?? '').toString().isNotEmpty) 'Серийный номер: ${row['serial_number']}',
              if ((row['location'] ?? '').toString().isNotEmpty) 'Место: ${row['location']}',
              if ((row['status'] ?? '').toString().isNotEmpty) 'Статус: ${row['status']}',
              if ((row['note'] ?? '').toString().isNotEmpty) 'Примечание: ${row['note']}',
            ].join('\n')),
            actions: [TextButton(onPressed: () => Navigator.pop(c), child: const Text('Закрыть'))],
          ),
        );
        return;
    }
    if (page != null && mounted) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => page!));
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Поиск по приложению')),
    body: Column(children: [
      Padding(
        padding: const EdgeInsets.all(16),
        child: TextField(
          controller: controller,
          autofocus: true,
          onChanged: search,
          decoration: InputDecoration(
            prefixIcon: const Icon(Icons.search),
            hintText: 'ФИО, инвентарный номер, модель…',
            border: const OutlineInputBorder(),
            suffixIcon: IconButton(
              icon: const Icon(Icons.clear),
              onPressed: () { controller.clear(); search(''); },
            ),
          ),
        ),
      ),
      Expanded(
        child: searching
            ? const Center(child: CircularProgressIndicator())
            : results.isEmpty
                ? Center(child: Text(controller.text.trim().isEmpty
                    ? 'Введите запрос для поиска по разделам'
                    : 'Ничего не найдено'))
                : ListView.builder(
                    itemCount: results.length,
                    itemBuilder: (context, index) {
                      final r = results[index];
                      return ListTile(
                        leading: const Icon(Icons.search),
                        title: Text(r['title'] as String),
                        subtitle: Text('${r['section']} · ${r['subtitle']}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => _openResult(r),
                      );
                    },
                  ),
      ),
    ]),
  );
}
