import 'package:decimal/decimal.dart';
import 'package:drift/drift.dart';

/// Stores [Decimal] as TEXT so money never passes through `double`.
///
/// Also a [JsonTypeConverter]: backups serialise rows with `toJson`, and
/// without it Drift would read a price back by casting the JSON string to
/// `Decimal` — which fails, so every backup with prices failed to import.
class DecimalConverter extends TypeConverter<Decimal, String>
    with JsonTypeConverter<Decimal, String> {
  const DecimalConverter();

  @override
  Decimal fromSql(String fromDb) => Decimal.parse(fromDb);

  @override
  String toSql(Decimal value) => value.toString();
}
