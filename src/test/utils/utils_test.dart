import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/services/backup_service.dart';
import 'package:price_alarm/core/utils/formatters.dart';
import 'package:price_alarm/core/utils/shop_name.dart';

void main() {
  group('shopNameFromUrl', () {
    test('derives the shop from the host', () {
      expect(
        shopNameFromUrl(
          'https://www.galaxus.ch/de/s1/product/asus-radeon-ai-pro-r9700-32-gb-gddr6-grafikkarte-60913447',
        ),
        'Galaxus',
      );
      expect(
        shopNameFromUrl(
          'https://www.brack.ch/asus-grafikkarte-turbo-radeon-ai-pro-r9700-1961443',
        ),
        'Brack',
      );
    });

    test('returns an empty string for garbage', () {
      expect(shopNameFromUrl('not a url'), '');
    });
  });

  group('validateOfferUrl', () {
    test('accepts https and rejects http or incomplete input', () {
      expect(validateOfferUrl('https://www.brack.ch/x'), isNull);
      expect(validateOfferUrl('http://www.brack.ch/x'), isNotNull);
      expect(validateOfferUrl('brack.ch/x'), isNotNull);
    });
  });

  group('formatters', () {
    test('formatCheckTime pads hours and minutes', () {
      expect(formatCheckTime(480), '08:00');
      expect(formatCheckTime(1439), '23:59');
      expect(formatCheckTime(5), '00:05');
    });

    test('formatMoney uses two decimals and the currency prefix', () {
      // The de_CH grouping character differs between intl/CLDR versions
      // (apostrophe vs. right single quotation mark), so only the stable
      // parts are asserted.
      final text = formatMoney(Decimal.parse('2209'), 'CHF');
      expect(text, startsWith('CHF 2'));
      expect(text, endsWith('209.00'));
    });

    test('formatUpcoming labels today and tomorrow', () {
      final now = DateTime(2026, 11, 21, 7);
      expect(formatUpcoming(DateTime(2026, 11, 21, 8), now), 'today 08:00');
      expect(formatUpcoming(DateTime(2026, 11, 22, 8), now), 'tomorrow 08:00');
    });
  });

  group('BackupService.fileName', () {
    test('uses a sortable timestamp', () {
      expect(
        BackupService.fileName(DateTime(2026, 11, 21, 8, 3, 9)),
        'pricealarm_20261121_080309.zip',
      );
    });
  });
}
