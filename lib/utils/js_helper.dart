// Conditional import — automatically picks the correct implementation
// Web    → js_helper_web.dart  (uses dart:js_interop)
// Mobile → js_helper_stub.dart (no-op stubs)
export 'js_helper_stub.dart'
    if (dart.library.js_interop) 'js_helper_web.dart';
