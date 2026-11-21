import 'package:drift/drift.dart';

import '../../models/enums.dart';
import '../decimal_converter.dart';
import 'items_table.dart';

@DataClassName('OfferRow')
class Offers extends Table {
  TextColumn get id => text()();
  TextColumn get itemId =>
      text().references(Items, #id, onDelete: KeyAction.cascade)();
  TextColumn get url => text()();
  TextColumn get shopName => text()();
  TextColumn get fetchMode =>
      textEnum<FetchMode>().withDefault(Constant(FetchMode.auto.name))();

  // The method that last succeeded under FetchMode.auto; tried first next
  // time so a shop that always blocks HTTP is not hit with a doomed request.
  TextColumn get resolvedMethod => textEnum<FetchMethod>().nullable()();

  TextColumn get lastPrice =>
      text().map(const DecimalConverter()).nullable()();
  TextColumn get lastCurrency => text().nullable()();
  TextColumn get lastAvailability => text().nullable()();
  TextColumn get lastStatus => textEnum<CheckStatus>().nullable()();
  TextColumn get lastError => text().nullable()();
  DateTimeColumn get lastCheckedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};

  @override
  List<Set<Column>> get uniqueKeys => [
    {itemId, url},
  ];
}
