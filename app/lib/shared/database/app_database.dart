// Drift schema for the app. Run `dart run build_runner build` to
// regenerate `app_database.g.dart` after editing.

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

  /// Non-null once the on-device pipeline has produced a successful result
  /// for this match. The library uses it to route tile taps and to badge
  /// processed matches.
  DateTimeColumn get processedAt => dateTime().nullable()();

  /// Source-video resolution captured during processing. Stored so the
  /// review-screen overlay can scale ball bounding boxes back into layout
  /// coordinates without re-opening the video.
  IntColumn get frameWidth => integer().nullable()();
  IntColumn get frameHeight => integer().nullable()();

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

  /// Observations always belong to a match.
  TextColumn get matchId => text().references(Matches, #id)();

  /// Observations may belong to a rally once rally segmentation runs.
  /// For milestone 5b they're all attached at the match level only.
  IntColumn get rallyId => integer().nullable().references(Rallies, #id)();
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
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
        },
        onUpgrade: (m, from, to) async {
          // Prototype convenience: no shipped data yet. Wipe and rebuild on
          // any version bump. Replace with a real migration once we have
          // installs to preserve.
          await customStatement('PRAGMA foreign_keys = OFF');
          for (final table in allTables) {
            await customStatement(
              'DROP TABLE IF EXISTS ${table.actualTableName}',
            );
          }
          await m.createAll();
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );
}

QueryExecutor _openConnection() {
  return LazyDatabase(() async {
    final dir = await getApplicationDocumentsDirectory();
    final file = File(p.join(dir.path, 'beach_stats.sqlite'));
    return NativeDatabase.createInBackground(file);
  });
}
