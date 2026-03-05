// Web implementation - uses dart:js_interop
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_interop';

@JS('eval')
external JSAny? _evalJsWeb(String code);

/// تنفيذ كود JavaScript على الويب
void evalJs(String code) {
  _evalJsWeb(code);
}

/// جلب قيمة boolean من JavaScript
bool evalJsBool(String code) {
  final result = _evalJsWeb(code);
  return result?.dartify() == true;
}

/// جلب قيمة String من JavaScript
String evalJsString(String code) {
  final result = _evalJsWeb(code);
  return (result?.dartify() as String?) ?? '';
}
