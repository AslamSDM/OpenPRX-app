import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'conversations_db.g.dart';

class Conversations extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get title => text().withDefault(const Constant('New chat'))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
}

class Messages extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get conversationId => integer().references(Conversations, #id, onDelete: KeyAction.cascade)();
  TextColumn get role => text()(); // system, user, assistant
  TextColumn get content => text()();
  TextColumn get mode => text().withDefault(const Constant('chat'))(); // chat, search, research
  TextColumn get sourcesJson => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

@DriftDatabase(tables: [Conversations, Messages])
class ConversationsDatabase extends _$ConversationsDatabase {
  ConversationsDatabase() : super(_openConnection());

  @override
  int get schemaVersion => 1;

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'openprx_conversations');
  }

  Future<List<Conversation>> allConversations() =>
      (select(conversations)..orderBy([(t) => OrderingTerm.desc(t.updatedAt)])).get();

  Future<Conversation> createConversation(String title) async {
    final id = await into(conversations).insert(
      ConversationsCompanion.insert(title: Value(title)),
    );
    return (select(conversations)..where((t) => t.id.equals(id))).getSingle();
  }

  Future<void> updateTitle(int id, String title) =>
      (update(conversations)..where((t) => t.id.equals(id))).write(
        ConversationsCompanion(title: Value(title), updatedAt: Value(DateTime.now())),
      );

  Future<void> touch(int id) =>
      (update(conversations)..where((t) => t.id.equals(id))).write(
        ConversationsCompanion(updatedAt: Value(DateTime.now())),
      );

  Future<void> deleteConversation(int id) =>
      (delete(conversations)..where((t) => t.id.equals(id))).go();

  Future<List<Message>> messagesFor(int conversationId) =>
      (select(messages)
            ..where((m) => m.conversationId.equals(conversationId))
            ..orderBy([(m) => OrderingTerm.asc(m.createdAt)]))
          .get();

  Future<int> addMessage(int conversationId, String role, String content,
          {String mode = 'chat', String? sourcesJson}) =>
      into(messages).insert(
        MessagesCompanion.insert(
          conversationId: conversationId,
          role: role,
          content: content,
          mode: Value(mode),
          sourcesJson: Value(sourcesJson),
        ),
      );

  Future<void> updateMessage(int id, String content, {String? sourcesJson}) =>
      (update(messages)..where((m) => m.id.equals(id))).write(
        MessagesCompanion(
          content: Value(content),
          sourcesJson: sourcesJson == null ? const Value.absent() : Value(sourcesJson),
        ),
      );

  Future<void> deleteAllMessages(int conversationId) =>
      (delete(messages)..where((m) => m.conversationId.equals(conversationId))).go();
}
