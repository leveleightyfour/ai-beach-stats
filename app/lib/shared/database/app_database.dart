// Drift database for the app. Run `dart run build_runner build` after
// editing the schema or annotations to regenerate `app_database.g.dart`.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

part 'app_database.g.dart';

@DataClassName('MatchRow')
class Matches extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get videoPath => text()();
  IntColumn get durationMs => integer()();
  DateTimeColumn get importedAt => dateTime()();
  TextColumn get thumbnailPath => text().nullable()();

  @override
  Set<Column<Object>> get primaryKey => {id};
}

@DataClassName('RallyRow')
class Rallies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get matchId => text().references(Matches, #id)();
  IntColumn get rallyIndex => integer()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
}

@DataClassName('TouchRow')
class Touches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get rallyId => integer().references(Rallies, #id)();
  IntColumn get timestampMs => integer()();
  IntColumn get playerSlot => integer()();
  RealColumn get ballX => real()();
  RealColumn get ballY => real()();
}

@DataClassName('BallObservationRow')
class BallObservations extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get rallyId => integer().references(Rallies, #id)();
  IntColumn get frameIndex => integer()();
  IntColumn get timestampMs => integer()();
  RealColumn get x => real()();
  RealColumn get y => real()();
  RealColumn get width => real()();
  RealColumn get height => real()();
  RealColumn get confidence => real()();
}

@DriftDatabase(tables: [Matches, Rallies, Touches, BallObservations])
class AppDatabase extends _$AppDatabase {
  AppDatabase() : super(_openConnection());
  AppDatabase.forTesting(super.executor);

  @override
  int get schemaVersion => 1;
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'beach_stats.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
