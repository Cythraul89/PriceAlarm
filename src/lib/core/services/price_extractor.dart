import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:equatable/equatable.dart';
import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

class ExtractedPrice extends Equatable {
  const ExtractedPrice({
    required this.price,
    this.currency,
    this.availability,
  });

  final Decimal price;
  final String? currency;

  /// Last segment of the schema.org URL: `InStock`, `OutOfStock`, …
  final String? availability;

  @override
  List<Object?> get props => [price, currency, availability];
}

/// Reads a product price from schema.org structured data. Pure — no I/O —
/// and shared by the HTTP and the WebView fetch path (REQUIREMENTS 4.1).
abstract final class PriceExtractor {
  /// `null` means the page loaded but carries no usable price. The caller
  /// must not guess one from page text.
  static ExtractedPrice? extract(String html) {
    final document = html_parser.parse(html);
    return _fromJsonLd(document) ?? _fromMetaTags(document);
  }

  /// Heuristic for a bot-challenge or access-denied page served with
  /// HTTP 200, so it is reported as `blocked` rather than `noPrice`.
  static bool looksLikeChallenge(String html) {
    final lower = html.toLowerCase();
    return _challengeMarkers.any(lower.contains);
  }

  static ExtractedPrice? _fromJsonLd(Document document) {
    final scripts = document.querySelectorAll(
      'script[type="application/ld+json"]',
    );
    for (final script in scripts) {
      final Object? decoded;
      try {
        decoded = jsonDecode(script.text);
      } on FormatException {
        continue; // one broken block must not hide a valid one
      }
      final result = _searchProduct(decoded);
      if (result != null) return result;
    }
    return null;
  }

  static ExtractedPrice? _searchProduct(Object? node) {
    if (node is List) {
      for (final element in node) {
        final result = _searchProduct(element);
        if (result != null) return result;
      }
      return null;
    }
    if (node is! Map) return null;
    if (_hasType(node, 'Product')) {
      final result = _fromOffers(node['offers']);
      if (result != null) return result;
    }
    // Containers such as {"@graph": [...]} or nested entities.
    for (final value in node.values) {
      if (value is Map || value is List) {
        final result = _searchProduct(value);
        if (result != null) return result;
      }
    }
    return null;
  }

  static ExtractedPrice? _fromOffers(Object? offers) {
    if (offers is List) {
      for (final offer in offers) {
        final result = _fromOffers(offer);
        if (result != null) return result;
      }
      return null;
    }
    if (offers is! Map) return null;

    final price =
        _parsePrice(offers['price']) ??
        _parsePrice(offers['lowPrice']) ??
        _parsePrice(_mapOrNull(offers['priceSpecification'])?['price']);
    if (price == null) {
      // AggregateOffer may nest the concrete offers.
      return _fromOffers(offers['offers']);
    }
    final currency =
        _string(offers['priceCurrency']) ??
        _string(_mapOrNull(offers['priceSpecification'])?['priceCurrency']);
    return ExtractedPrice(
      price: price,
      currency: currency?.toUpperCase(),
      availability: _availability(offers['availability']),
    );
  }

  static ExtractedPrice? _fromMetaTags(Document document) {
    String? meta(String property) => document
        .querySelector('meta[property="$property"]')
        ?.attributes['content'];
    final price = _parsePrice(meta('product:price:amount'));
    if (price == null) return null;
    return ExtractedPrice(
      price: price,
      currency: meta('product:price:currency')?.toUpperCase(),
    );
  }

  static bool _hasType(Map<dynamic, dynamic> node, String type) {
    final value = node['@type'];
    if (value is String) return value == type || value.endsWith('/$type');
    if (value is List) return value.contains(type);
    return false;
  }

  /// Accepts JSON numbers and strings like `2209.00`, `2209`, `2'209.00`,
  /// `2209,50`. Anything else, and prices <= 0, yield `null`.
  static Decimal? _parsePrice(Object? raw) {
    String? text;
    if (raw is num) text = raw.toString();
    if (raw is String) text = raw;
    if (text == null) return null;
    var cleaned = text.trim().replaceAll(RegExp(r"[\s'’]"), '');
    if (!cleaned.contains('.') && cleaned.contains(',')) {
      cleaned = cleaned.replaceAll(',', '.');
    }
    if (!RegExp(r'^\d+(\.\d+)?$').hasMatch(cleaned)) return null;
    final value = Decimal.parse(cleaned);
    return value > Decimal.zero ? value : null;
  }

  static String? _availability(Object? raw) {
    final value = _string(raw);
    if (value == null) return null;
    return value.split('/').last;
  }

  static String? _string(Object? raw) =>
      raw is String && raw.trim().isNotEmpty ? raw.trim() : null;

  static Map<dynamic, dynamic>? _mapOrNull(Object? raw) =>
      raw is Map ? raw : null;
}

const _challengeMarkers = [
  'access denied',
  'captcha',
  'cf-challenge',
  'challenge-platform',
  'just a moment...',
  'are you a robot',
];
