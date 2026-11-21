import 'package:drift/drift.dart';

import '../../models/enums.dart';
import '../decimal_converter.dart';
import 'offers_table.dart';

@DataClassName('PriceCheckRow')
@TableIndex(name: 'price_checks_offer_time', columns: {#offerId, #checkedAt})
class PriceChecks extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get offerId =>
      text().references(Offers, #id, onDelete: KeyAction.cascade)();
  DateTimeColumn get checkedAt => dateTime()();
  TextColumn get status => textEnum<CheckStatus>()();
  TextColumn get method => textEnum<FetchMethod>().nullable()();
  TextColumn get price => text().map(const DecimalConverter()).nullable()();
  TextColumn get currency => text().nullable()();
  TextColumn get availability => text().nullable()();
  TextColumn get error => text().nullable()();
}
