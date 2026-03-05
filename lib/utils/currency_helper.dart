/// Shared currency utilities for Vinex Technology
/// Currency: Iraqi Dinar (IQD)
class CurrencyHelper {
  /// Format a number as Iraqi Dinar
  /// e.g. 1500000 → "IQD 1,500,000"
  static String format(double amount) {
    final intVal = amount.toInt();
    // Add thousand separators
    final formatted = _addThousandSeparators(intVal);
    return 'IQD $formatted';
  }

  static String _addThousandSeparators(int value) {
    final str = value.abs().toString();
    final buffer = StringBuffer();
    final len = str.length;
    for (int i = 0; i < len; i++) {
      if (i > 0 && (len - i) % 3 == 0) {
        buffer.write(',');
      }
      buffer.write(str[i]);
    }
    return value < 0 ? '-${buffer.toString()}' : buffer.toString();
  }
}
