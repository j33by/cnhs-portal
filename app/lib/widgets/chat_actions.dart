import 'package:flutter/material.dart';
import '../core/chat_data.dart';
import '../core/offline.dart';
import '../screens/student/messages_screen.dart';
import '../screens/student/room_screen.dart';
import '../screens/teacher/teacher_messages.dart';

/// Top-bar shortcuts shown on every tab: "Room" (people + voice messages) and "Messages" (with an unread counter).
class ChatActions extends StatelessWidget {
  final bool teacher;
  const ChatActions({super.key, this.teacher = false});

  @override
  Widget build(BuildContext c) => Row(mainAxisSize: MainAxisSize.min, children: [
        IconButton(tooltip: 'Room', icon: const Icon(Icons.meeting_room_outlined),
            onPressed: () => pushOnce(c, MaterialPageRoute(builder: (_) => teacher ? const TeacherRoomsScreen() : const RoomScreen()))),
        StreamBuilder<JRows>(stream: ChatData.threads(), builder: (c, ts) => StreamBuilder<JRows>(stream: ChatData.reads(), builder: (c, rs) {
          final read = ChatData.readMap(rs.data ?? const []);
          final n = (ts.data ?? const <Map<String, dynamic>>[]).where((t) => ChatData.isUnread(t, read)).length;
          return IconButton(tooltip: 'Messages', icon: Badge(isLabelVisible: n > 0, label: Text('$n'), child: const Icon(Icons.forum_outlined)),
              onPressed: () => pushOnce(c, MaterialPageRoute(builder: (_) => teacher ? const TeacherMessagesScreen() : const MessagesScreen())));
        })),
      ]);
}
