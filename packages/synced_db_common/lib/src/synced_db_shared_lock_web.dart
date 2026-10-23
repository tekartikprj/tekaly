import 'dart:js_interop';
import 'dart:js_interop_unsafe';

/// The Web Locks API (`navigator.locks`), null when missing (an older
/// browser, node).
JSObject? get _lockManager {
  var navigator = globalContext['navigator'];
  if (!navigator.isA<JSObject>()) {
    return null;
  }
  var locks = (navigator as JSObject)['locks'];
  if (!locks.isA<JSObject>()) {
    return null;
  }
  return locks as JSObject;
}

/// Run [action] holding the lock [name] shared by the browser tabs of the
/// same origin (Web Locks API): the other tabs requesting it wait until
/// [action] is done. Without the API [action] runs at once.
Future<T> syncedDbSharedLock<T>(
  String name,
  Future<T> Function() action,
) async {
  var lockManager = _lockManager;
  if (lockManager == null) {
    return action();
  }
  // The result and the error stay on the Dart side: the promise given to the
  // lock always resolves, which releases it.
  late T result;
  Object? error;
  StackTrace? stackTrace;
  Future<void> run() async {
    try {
      result = await action();
    } catch (e, st) {
      error = e;
      stackTrace = st;
    }
  }

  await lockManager
      .callMethod<JSPromise<JSAny?>>(
        'request'.toJS,
        name.toJS,
        ((JSAny? lock) => run().toJS).toJS,
      )
      .toDart;
  if (error != null) {
    Error.throwWithStackTrace(error!, stackTrace!);
  }
  return result;
}
