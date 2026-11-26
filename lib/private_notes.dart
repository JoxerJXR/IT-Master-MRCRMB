import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

class PrivateNotesPage extends StatefulWidget {
  const PrivateNotesPage({super.key});
  @override State<PrivateNotesPage> createState()=>_PrivateNotesPageState();
}
class _PrivateNotesPageState extends State<PrivateNotesPage>{
  static const storage=FlutterSecureStorage();
  static const key='it_master_private_notes_v1';
  static const pinKey='it_master_notes_pin';
  final controller=TextEditingController();
  bool loading=true,saving=false,visible=false;
  @override void initState(){super.initState();_load();}
  Future<void> _load() async {
    try{controller.text=await storage.read(key:key)??'';}catch(e){if(mounted)ScaffoldMessenger.of(context).showSnackBar(SnackBar(content:Text('Не удалось прочитать защищённые заметки: $e')));}
    if(mounted)setState(()=>loading=false);
  }
  Future<void> _setVisible(bool value) async {
    if (!value) {
      if (mounted) setState(() => visible = false);
      return;
    }
    final savedPin = await storage.read(key: pinKey);
    if (savedPin == null || savedPin.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Сначала установите отдельный PIN заметок в настройках приложения.')),
        );
      }
      return;
    }
    final pinController = TextEditingController();
    final enteredPin = await showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Защита заметок'),
        content: TextField(
          controller: pinController,
          autofocus: true,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 8,
          decoration: const InputDecoration(
            labelText: 'PIN заметок',
            helperText: 'Введите отдельный PIN-код для просмотра текста',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.pop(dialogContext, value),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(dialogContext), child: const Text('Отмена')),
          FilledButton(onPressed: () => Navigator.pop(dialogContext, pinController.text), child: const Text('Показать')),
        ],
      ),
    );
    pinController.dispose();
    if (!mounted || enteredPin == null) return;
    if (enteredPin != savedPin) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Неверный PIN заметок')),
      );
      return;
    }
    setState(() => visible = true);
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
      SwitchListTile(contentPadding:EdgeInsets.zero,value:visible,onChanged:_setVisible,title:const Text('Показывать текст')),
      FilledButton.icon(onPressed:saving?null:_save,icon:const Icon(Icons.lock),label:Text(saving?'Сохранение…':'Сохранить защищённые заметки')),
    ]));
}
