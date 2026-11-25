import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';
import 'cartridges.dart';

class EquipmentPage extends StatefulWidget {
  const EquipmentPage({super.key});
  @override
  State<EquipmentPage> createState() => _EquipmentPageState();
}
class _EquipmentPageState extends State<EquipmentPage> {
  List<Map<String,Object?>> items=[];
  bool loading=true;
  String filter='Все', search='';
  Future<Database> get db => CartridgeDatabase.instance.database;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    final d=await db;
    await d.execute("""CREATE TABLE IF NOT EXISTS it_equipment (
      id INTEGER PRIMARY KEY AUTOINCREMENT,title TEXT NOT NULL,
      category TEXT NOT NULL DEFAULT 'Другое',model TEXT NOT NULL DEFAULT '',
      inventory_number TEXT NOT NULL DEFAULT '',serial_number TEXT NOT NULL DEFAULT '',
      location TEXT NOT NULL DEFAULT '',status TEXT NOT NULL DEFAULT 'Исправно',
      fault_reason TEXT NOT NULL DEFAULT '',note TEXT NOT NULL DEFAULT '',
      updated_at TEXT NOT NULL)""");
    final rows=await d.query('it_equipment',orderBy:'title COLLATE NOCASE');
    if(mounted)setState(()=>{items=rows,loading=false});
  }
  Future<void> _edit([Map<String,Object?>? item]) async {
    final ok=await Navigator.push<bool>(context,MaterialPageRoute(builder:(_)=>EquipmentEditPage(item:item)));
    if(ok==true)_load();
  }
  Future<void> _delete(Map<String,Object?> e) async {
    final ok=await showDialog<bool>(context:context,builder:(c)=>AlertDialog(
      title:const Text('Удалить оборудование?'),
      content:Text('Удалить запись «'+(e['title'] as String)+'»?'),
      actions:[TextButton(onPressed:()=>Navigator.pop(c,false),child:const Text('Отмена')),
        FilledButton(onPressed:()=>Navigator.pop(c,true),child:const Text('Удалить'))]));
    if(ok==true){await (await db).delete('it_equipment',where:'id=?',whereArgs:[e['id']]);_load();}
  }
  @override Widget build(BuildContext context){
    final visible=items.where((e){
      final q=search.toLowerCase();
      final matches= q.isEmpty || ['title','category','model','location','inventory_number','serial_number']
        .any((k)=>(e[k]??'').toString().toLowerCase().contains(q));
      return matches && (filter=='Все'||e['status']==filter);
    }).toList();
    return Scaffold(
      floatingActionButton:FloatingActionButton.extended(onPressed:()=>_edit(),icon:const Icon(Icons.add),label:const Text('Добавить')),
      body:loading?const Center(child:CircularProgressIndicator()):RefreshIndicator(
        onRefresh:_load,child:ListView(padding:const EdgeInsets.fromLTRB(16,12,16,90),children:[
          Row(children:[
            _stat('Всего',items.length,Icons.devices),
            _stat('Исправно',items.where((e)=>e['status']=='Исправно').length,Icons.check_circle_outline),
            _stat('Неисправно',items.where((e)=>e['status']=='Неисправно').length,Icons.warning_amber),
          ]),
          const SizedBox(height:12),
          TextField(decoration:const InputDecoration(prefixIcon:Icon(Icons.search),hintText:'Поиск оборудования',border:OutlineInputBorder()),onChanged:(v)=>setState(()=>search=v)),
          const SizedBox(height:10),
          Wrap(spacing:7,children:['Все','Исправно','Неисправно','На обслуживании'].map((v)=>ChoiceChip(label:Text(v),selected:filter==v,onSelected:(_)=>setState(()=>filter=v))).toList()),
          const SizedBox(height:10),
          if(visible.isEmpty) const Padding(padding:EdgeInsets.only(top:45),child:Text('Записей пока нет. Нажмите «Добавить».',textAlign:TextAlign.center))
          else ...visible.map((e)=>Card(elevation:0,margin:const EdgeInsets.only(bottom:8),child:ListTile(
            leading:CircleAvatar(child:Icon(_icon(e['category'] as String))),
            title:Text(e['title'] as String,style:const TextStyle(fontWeight:FontWeight.w600)),
            subtitle:Column(crossAxisAlignment:CrossAxisAlignment.start,children:[
              if((e['model'] as String).isNotEmpty)Text('Модель: '+(e['model'] as String)),
              if((e['location'] as String).isNotEmpty)Text('Место: '+(e['location'] as String)),
              Text('Состояние: '+(e['status'] as String)),
              if((e['fault_reason'] as String).isNotEmpty)Text('Причина: '+(e['fault_reason'] as String),style:TextStyle(color:Theme.of(context).colorScheme.error)),
            ]),
            isThreeLine:true,onTap:()=>_edit(e),
            trailing:PopupMenuButton<String>(onSelected:(v){if(v=='edit')_edit(e);if(v=='delete')_delete(e);},itemBuilder:(_)=>const [
              PopupMenuItem(value:'edit',child:Text('Редактировать')),
              PopupMenuItem(value:'delete',child:Text('Удалить'))])))),
        ])));
  }
  Widget _stat(String label,int n,IconData icon)=>Expanded(child:Card(elevation:0,child:Padding(padding:const EdgeInsets.all(8),child:Column(children:[Icon(icon),Text('$n',style:const TextStyle(fontWeight:FontWeight.bold,fontSize:19)),Text(label,style:const TextStyle(fontSize:11))]))));
  IconData _icon(String c)=>c=='Принтер'?Icons.print:c=='Компьютер'||c=='Ноутбук'?Icons.computer:c=='Монитор'?Icons.monitor:c=='Сетевое оборудование'?Icons.router:Icons.devices_other;
}

class EquipmentEditPage extends StatefulWidget {
  final Map<String,Object?>? item;
  const EquipmentEditPage({super.key,this.item});
  @override State<EquipmentEditPage> createState()=>_EquipmentEditPageState();
}
class _EquipmentEditPageState extends State<EquipmentEditPage>{
  final keyForm=GlobalKey<FormState>();
  late TextEditingController title,model,inventory,serial,location,fault,note;
  String category='Принтер',status='Исправно';
  @override void initState(){
    super.initState();final e=widget.item;
    title=TextEditingController(text:e?['title'] as String? ?? '');
    model=TextEditingController(text:e?['model'] as String? ?? '');
    inventory=TextEditingController(text:e?['inventory_number'] as String? ?? '');
    serial=TextEditingController(text:e?['serial_number'] as String? ?? '');
    location=TextEditingController(text:e?['location'] as String? ?? '');
    fault=TextEditingController(text:e?['fault_reason'] as String? ?? '');
    note=TextEditingController(text:e?['note'] as String? ?? '');
    category=e?['category'] as String? ?? 'Принтер';status=e?['status'] as String? ?? 'Исправно';
  }
  @override void dispose(){for(final c in [title,model,inventory,serial,location,fault,note]){c.dispose();}super.dispose();}
  Future<void> _save() async{
    if(!keyForm.currentState!.validate())return;
    final d=await CartridgeDatabase.instance.database;
    final values=<String,Object?>{'title':title.text.trim(),'category':category,'model':model.text.trim(),
      'inventory_number':inventory.text.trim(),'serial_number':serial.text.trim(),'location':location.text.trim(),
      'status':status,'fault_reason':status=='Неисправно'?fault.text.trim():'',
      'note':note.text.trim(),'updated_at':DateTime.now().toIso8601String()};
    if(widget.item==null){await d.insert('it_equipment',values);}else{await d.update('it_equipment',values,where:'id=?',whereArgs:[widget.item!['id']]);}
    if(mounted)Navigator.pop(context,true);
  }
  Widget _field(TextEditingController c,String label,{int lines=1})=>Padding(padding:const EdgeInsets.only(bottom:11),child:TextFormField(controller:c,maxLines:lines,decoration:InputDecoration(labelText:label,border:const OutlineInputBorder())));
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:Text(widget.item==null?'Новое оборудование':'Редактирование оборудования')),
    body:Form(key:keyForm,child:ListView(padding:const EdgeInsets.all(16),children:[
      TextFormField(controller:title,decoration:const InputDecoration(labelText:'Название оборудования *',border:OutlineInputBorder()),validator:(v)=>v==null||v.trim().isEmpty?'Укажите название':null),
      const SizedBox(height:11),
      DropdownButtonFormField<String>(value:category,decoration:const InputDecoration(labelText:'Категория',border:OutlineInputBorder()),
        items:['Принтер','Компьютер','Ноутбук','Монитор','Сетевое оборудование','Периферия','Другое'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>category=v??category)),
      const SizedBox(height:11),
      _field(model,'Модель / производитель'),_field(inventory,'Инвентарный номер'),_field(serial,'Серийный номер'),_field(location,'Где хранится / местонахождение'),
      DropdownButtonFormField<String>(value:status,decoration:const InputDecoration(labelText:'Состояние',border:OutlineInputBorder()),
        items:['Исправно','Неисправно','На обслуживании'].map((v)=>DropdownMenuItem(value:v,child:Text(v))).toList(),onChanged:(v)=>setState(()=>status=v??status)),
      if(status=='Неисправно')...[
        const SizedBox(height:11),
        TextFormField(controller:fault,maxLines:3,decoration:const InputDecoration(labelText:'Причина неисправности *',border:OutlineInputBorder()),validator:(v)=>status=='Неисправно'&&(v==null||v.trim().isEmpty)?'Опишите неисправность':null)],
      const SizedBox(height:11),_field(note,'Примечание',lines:3),
      const SizedBox(height:18),FilledButton.icon(onPressed:_save,icon:const Icon(Icons.save),label:const Text('Сохранить')),
    ])));
}
