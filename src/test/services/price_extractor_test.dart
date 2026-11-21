import 'dart:io';

import 'package:decimal/decimal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:price_alarm/core/services/price_extractor.dart';

String _page(String head) => '<html><head>$head</head><body></body></html>';

String _jsonLd(String json) =>
    _page('<script type="application/ld+json">$json</script>');

void main() {
  group('PriceExtractor.extract', () {
    test('reads price, currency and availability from the real Brack page', () {
      final html = File(
        'test/fixtures/brack_r9700_2026-11-21.html',
      ).readAsStringSync();
      expect(
        PriceExtractor.extract(html),
        ExtractedPrice(
          price: Decimal.parse('2209.00'),
          currency: 'CHF',
          availability: 'OutOfStock',
        ),
      );
    });

    test('accepts a JSON number as price', () {
      final result = PriceExtractor.extract(
        _jsonLd(
          '{"@type":"Product","offers":{"@type":"Offer","price":2209,'
          '"priceCurrency":"CHF"}}',
        ),
      );
      expect(result?.price, Decimal.fromInt(2209));
    });

    test('finds a Product inside @graph and strips the schema.org URL '
        'from availability', () {
      final result = PriceExtractor.extract(
        _jsonLd(
          '{"@context":"https://schema.org","@graph":['
          '{"@type":"WebSite","name":"Shop"},'
          '{"@type":"Product","offers":{"@type":"Offer","price":"99.90",'
          '"priceCurrency":"chf",'
          '"availability":"https://schema.org/InStock"}}]}',
        ),
      );
      expect(
        result,
        ExtractedPrice(
          price: Decimal.parse('99.90'),
          currency: 'CHF',
          availability: 'InStock',
        ),
      );
    });

    test('uses lowPrice of an AggregateOffer', () {
      final result = PriceExtractor.extract(
        _jsonLd(
          '{"@type":"Product","offers":{"@type":"AggregateOffer",'
          '"lowPrice":"1899.00","highPrice":"2300.00","priceCurrency":"CHF"}}',
        ),
      );
      expect(result?.price, Decimal.parse('1899.00'));
    });

    test('uses the first priced offer of an offer list', () {
      final result = PriceExtractor.extract(
        _jsonLd(
          '{"@type":"Product","offers":[{"@type":"Offer"},'
          '{"@type":"Offer","price":"10.50","priceCurrency":"EUR"}]}',
        ),
      );
      expect(result?.price, Decimal.parse('10.50'));
      expect(result?.currency, 'EUR');
    });

    test("parses Swiss-formatted strings like 2'209.00 and 2209,50", () {
      String product(String price) => _jsonLd(
        '{"@type":"Product","offers":{"price":"$price"}}',
      );
      expect(
        PriceExtractor.extract(product("2'209.00"))?.price,
        Decimal.parse('2209.00'),
      );
      expect(
        PriceExtractor.extract(product('2209,50'))?.price,
        Decimal.parse('2209.50'),
      );
    });

    test('skips a malformed JSON-LD block and reads the next one', () {
      final html = _page(
        '<script type="application/ld+json">{not json</script>'
        '<script type="application/ld+json">'
        '{"@type":"Product","offers":{"price":"5.00"}}</script>',
      );
      expect(PriceExtractor.extract(html)?.price, Decimal.parse('5.00'));
    });

    test('falls back to Open Graph product meta tags', () {
      final html = _page(
        '<meta property="product:price:amount" content="349.00">'
        '<meta property="product:price:currency" content="CHF">',
      );
      expect(
        PriceExtractor.extract(html),
        ExtractedPrice(price: Decimal.parse('349.00'), currency: 'CHF'),
      );
    });

    test('returns null when the page has no structured price', () {
      expect(PriceExtractor.extract(_page('<title>Product</title>')), isNull);
    });

    test('returns null for a zero or non-numeric price', () {
      expect(
        PriceExtractor.extract(
          _jsonLd('{"@type":"Product","offers":{"price":"0.00"}}'),
        ),
        isNull,
      );
      expect(
        PriceExtractor.extract(
          _jsonLd('{"@type":"Product","offers":{"price":"on request"}}'),
        ),
        isNull,
      );
    });

    test('ignores offers that are not attached to a Product', () {
      expect(
        PriceExtractor.extract(
          _jsonLd('{"@type":"Offer","price":"10.00"}'),
        ),
        isNull,
      );
    });
  });

  group('PriceExtractor.looksLikeChallenge', () {
    test('detects an Akamai access-denied page', () {
      expect(
        PriceExtractor.looksLikeChallenge(
          '<html><head><title>Access Denied</title></head></html>',
        ),
        isTrue,
      );
    });

    test('does not flag the real Brack product page', () {
      final html = File(
        'test/fixtures/brack_r9700_2026-11-21.html',
      ).readAsStringSync();
      expect(PriceExtractor.looksLikeChallenge(html), isFalse);
    });
  });
}
