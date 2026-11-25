import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateNotesPage extends StatefulWidget {
  const PrivateNotesPage({super.key});
  @override State<PrivateNotesPage> createState()=>_PrivateNotesPageState();
}
class _PrivateNotesPageState extends State<PrivateNotesPage>{
  static const storage=FlutterSecureStorage();
  static const key='it_master_private_notes_v1';
  final controller=TextEditingController();
  bool loading=true,saving=false,visible=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    try{controller.text=await storage.read(key:key)??'';}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Не удалось прочитать защищённые заметки: $e')));}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> _save() async{
    setState(()=>saving=true);
    try{await storage.write(key:key,value:controller.text);if(mounted)ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content:Text('Заметки сохранены в защищённом хранилище телефона.')));}
    catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Ошибка сохранения: $e')));}
    if(mounted)setState(()=>saving=false);
  }
  @override void dispose(){controller.dispose();super.dispose();}
  @override Widget build(BuildContext context)=>Scaffold(
    appBar:AppBar(title:const Text('Личные заметки')),
    body:loading?const Center(child:CircularProgressIndicator()):ListView(padding:const EdgeInsets.all(16),children:[
      const Card(child:Padding(padding:EdgeInsets.all(12),child:Text('Здесь можно хранить Wi‑Fi сети, пароли, имена компьютеров и рабочие учётные записи. Данные сохраняются в защищённом хранилище Android на этом телефоне и не отправляются в GitHub. Не записывайте пароли от критически важных систем, если телефон не защищён PIN-кодом/биометрией.'))),
      const SizedBox(height:12),
      TextField(controller:controller,minLines:12,maxLines:30,obscureText:!visible,decoration:const InputDecoration(labelText:'Мои записи',hintText:'Wi‑Fi: название сети…\nКомпьютер: имя / IP…\nУчётная запись: логин…',alignLabelWithHint:true,border:OutlineInputBorder())),
      SwitchListTile(contentPadding:EdgeInsets.zero,value:visible,onChanged:(v)=>setState(()=>visible=v),title:const Text('Показывать текст')),
      FilledButton.icon(onPressed:saving?null:_save,icon:const Icon(Icons.lock),label:Text(saving?'Сохранение…':'Сохранить защищённые заметки')),
    ]));
}
