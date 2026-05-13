// Drift schema for the app. Tables match the milestone-1 persistence model.
//
// Run `dart run build_runner build` to regenerate `app_database.g.dart`
// after editing the schema.

import 'package:drift/drift.dart';

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

class Rallies extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get matchId => text().references(Matches, #id)();
  IntColumn get rallyIndex => integer()();
  IntColumn get startMs => integer()();
  IntColumn get endMs => integer()();
}

class Touches extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get rallyId => integer().references(Rallies, #id)();
  IntColumn get timestampMs => integer()();
  IntColumn get playerSlot => integer()();
  RealColumn get ballX => real()();
  RealColumn get ballY => real()();
}

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

// AppDatabase class deliberately omitted from this scaffold — wire it up
// once we're ready to persist results from the pipeline. Drift's
// `@DriftDatabase(tables: [...])` annotation goes here, generating
// `app_database.g.dart`.
