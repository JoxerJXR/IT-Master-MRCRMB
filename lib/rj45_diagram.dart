import 'package:flutter/material.dart';

class RJ45WiringCard extends StatelessWidget {
  const RJ45WiringCard({super.key});

  static const _b = <_Wire>[
    _Wire('Б/О', Color(0xFFF5F5F5), Color(0xFFFF8A00)),
    _Wire('О', Color(0xFFFF8A00), Color(0xFFFF8A00)),
    _Wire('Б/З', Color(0xFFF5F5F5), Color(0xFF2E9D55)),
    _Wire('С', Color(0xFF2878D0), Color(0xFF2878D0)),
    _Wire('Б/С', Color(0xFFF5F5F5), Color(0xFF2878D0)),
    _Wire('З', Color(0xFF2E9D55), Color(0xFF2E9D55)),
    _Wire('Б/К', Color(0xFFF5F5F5), Color(0xFF80543A)),
    _Wire('К', Color(0xFF80543A), Color(0xFF80543A)),
  ];
  static const _a = <_Wire>[
    _Wire('Б/З', Color(0xFFF5F5F5), Color(0xFF2E9D55)),
    _Wire('З', Color(0xFF2E9D55), Color(0xFF2E9D55)),
    _Wire('Б/О', Color(0xFFF5F5F5), Color(0xFFFF8A00)),
    _Wire('С', Color(0xFF2878D0), Color(0xFF2878D0)),
    _Wire('Б/С', Color(0xFFF5F5F5), Color(0xFF2878D0)),
    _Wire('О', Color(0xFFFF8A00), Color(0xFFFF8A00)),
    _Wire('Б/К', Color(0xFFF5F5F5), Color(0xFF80543A)),
    _Wire('К', Color(0xFF80543A), Color(0xFF80543A)),
  ];

  @override
  Widget build(BuildContext context) => Card(
    elevation: 0,
    child: Padding(
      padding: const EdgeInsets.all(14),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Цветовая схема обжима RJ45', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        const SizedBox(height: 5),
        const Text('Вид со стороны золотых контактов. Контакт 1 — слева.'),
        const SizedBox(height: 12),
        _row('T568B', _b),
        const SizedBox(height: 10),
        _row('T568A', _a),
        const SizedBox(height: 10),
        const Text('Прямой кабель: одинаковая схема на обоих концах. Перекрёстный: T568A на одном конце и T568B на другом.', style: TextStyle(fontSize: 12)),
      ]),
    ),
  );

  Widget _row(String title, List<_Wire> wires) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
      const SizedBox(height: 6),
      Row(children: [
        for (var i = 0; i < wires.length; i++)
          Expanded(child: Padding(
            padding: EdgeInsets.only(right: i == wires.length - 1 ? 0 : 3),
            child: Column(children: [
              Container(
                height: 34,
                decoration: BoxDecoration(color: wires[i].base, border: Border.all(color: Colors.black26), borderRadius: BorderRadius.circular(4)),
                alignment: Alignment.center,
                child: wires[i].base == const Color(0xFFF5F5F5) ? Container(height: 5, color: wires[i].stripe) : null,
              ),
              const SizedBox(height: 3),
              Text('${i + 1}', style: const TextStyle(fontSize: 10)),
              Text(wires[i].label, style: const TextStyle(fontSize: 8), textAlign: TextAlign.center),
            ]),
          )),
      ]),
    ],
  );
}

class _Wire {
  final String label;
  final Color base;
  final Color stripe;
  const _Wire(this.label, this.base, this.stripe);
}