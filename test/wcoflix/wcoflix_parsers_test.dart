import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:kartoonia/services/wcoflix/wcoflix_parsers.dart';

String fx(String n) => File('test/fixtures/wcoflix/$n').readAsStringSync();

void main() {
  test('parseSidebarTitles finds popular links', () {
    final list = parseSidebarTitles(fx('home.html'));
    expect(list, isNotEmpty);
    expect(list.first.url, startsWith('http'));
    expect(list.first.title, isNotEmpty);
  });

  test('parseDdmccList finds many A-Z series links, skips letter anchors', () {
    final list = parseDdmccList(fx('cartoon_list.html'));
    expect(list.length, greaterThan(50));
    expect(list.any((e) => e.title == 'A' || e.title == '#'), isFalse);
    expect(list.every((e) => e.url.startsWith('http')), isTrue);
  });

  test('parseDdmccList handles the <li data-id="N"> (Dubbed) shape', () {
    const html = '<div class="ddmcc"><ul class="tooltip">'
        '<li data-id="3">\n<a href="/anime/bleach?lang=dub">Bleach</a></li>'
        '<li><a href="/anime/naruto">Naruto</a></li>'
        '</ul></div><script>x</script>';
    final list = parseDdmccList(html);
    expect(list.map((e) => e.title), containsAll(['Bleach', 'Naruto']));
  });

  test('parseSearchResults finds results', () {
    final list = parseSearchResults(fx('search.html'));
    expect(list, isNotEmpty);
    expect(list.first.url, contains('/anime/'));
  });

  test('parseSeriesPage returns episodes (slug-filtered) + poster', () {
    final s = parseSeriesPage(fx('series.html'), 'black-torch');
    expect(s.episodes, isNotEmpty);
    expect(s.episodes.every((e) => e.url.contains('black-torch')), isTrue);
    expect(s.episodes.every((e) => e.url.contains('episode')), isTrue);
    expect(s.poster, isNotNull);
  });

  test('seriesSlugFromUrl strips /anime/', () {
    expect(seriesSlugFromUrl('https://www.wcoflix.tv/anime/black-torch'),
        'black-torch');
    expect(seriesSlugFromUrl('/anime/2-stupid-dogs'), '2-stupid-dogs');
  });
}
