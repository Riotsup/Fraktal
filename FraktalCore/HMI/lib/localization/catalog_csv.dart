library;

enum CatalogScope { standard, project }

class CatalogCsv {
  static String encode({
    required CatalogScope scope,
    required String locale,
    required Map<String, String> values,
  }) {
    final out = StringBuffer('schemaVersion,scope,locale,key,value\r\n');
    final keys = values.keys.toList()..sort();
    for (final key in keys) {
      out
        ..write('1,')
        ..write(scope.name)
        ..write(',')
        ..write(_quote(locale))
        ..write(',')
        ..write(_quote(key))
        ..write(',')
        ..write(_quote(values[key] ?? ''))
        ..write('\r\n');
    }
    return out.toString();
  }

  static Map<String, String> decode(
    String csv, {
    required CatalogScope expectedScope,
    required String expectedLocale,
  }) {
    final rows = _rows(csv);
    if (rows.isEmpty ||
        rows.first.join(',') != 'schemaVersion,scope,locale,key,value') {
      throw const FormatException('Invalid catalog header');
    }
    final values = <String, String>{};
    for (final row in rows.skip(1)) {
      if (row.length != 5 || row.every((cell) => cell.isEmpty)) continue;
      if (row[0] != '1' ||
          row[1] != expectedScope.name ||
          row[2] != expectedLocale ||
          row[3].trim().isEmpty) {
        throw const FormatException('Catalog metadata/key mismatch');
      }
      final key = row[3].trim();
      final validPrefix = expectedScope == CatalogScope.standard
          ? key.startsWith('std.')
          : key.startsWith('project.');
      if (!validPrefix || values.containsKey(key)) {
        throw const FormatException('Catalog key scope/duplicate mismatch');
      }
      values[key] = row[4];
    }
    if (values.isEmpty) throw const FormatException('Empty catalog');
    return values;
  }

  static String _quote(String value) => '"${value.replaceAll('"', '""')}"';

  static List<List<String>> _rows(String input) {
    final rows = <List<String>>[];
    var row = <String>[];
    var cell = StringBuffer();
    var quoted = false;
    for (var i = 0; i < input.length; i++) {
      final char = input[i];
      if (quoted) {
        if (char == '"') {
          if (i + 1 < input.length && input[i + 1] == '"') {
            cell.write('"');
            i++;
          } else {
            quoted = false;
          }
        } else {
          cell.write(char);
        }
      } else if (char == '"') {
        quoted = true;
      } else if (char == ',') {
        row.add(cell.toString());
        cell = StringBuffer();
      } else if (char == '\n') {
        row.add(cell.toString().replaceFirst(RegExp(r'\r$'), ''));
        rows.add(row);
        row = <String>[];
        cell = StringBuffer();
      } else {
        cell.write(char);
      }
    }
    if (quoted) throw const FormatException('Unclosed CSV quote');
    if (cell.isNotEmpty || row.isNotEmpty) {
      row.add(cell.toString().replaceFirst(RegExp(r'\r$'), ''));
      rows.add(row);
    }
    return rows;
  }
}
