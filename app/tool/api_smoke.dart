// ignore_for_file: avoid_print

import 'package:chatvv/data/remote_chat_api.dart';
import 'package:chatvv/features/chat/chat_models.dart';

Future<void> main() async {
  final api = RemoteChatApi(baseUrl: 'http://127.0.0.1:8080');
  final history = await api.history(limit: 3);
  print('history=${history.length}');
  var text = '';
  var completed = false;
  var id = '';
  await for (final event in api.send('smoke test')) {
    switch (event.type) {
      case ChatStreamEventType.started:
        id = event.responseId ?? '';
        break;
      case ChatStreamEventType.delta:
        text += event.delta ?? '';
        break;
      case ChatStreamEventType.completed:
        completed = true;
        break;
      case ChatStreamEventType.failed:
        print('failed=${event.error}');
        break;
    }
  }
  print('id=$id completed=$completed textLen=${text.length}');
  print(text);
  api.dispose();
}
