/// Run [action] holding the lock [name] shared by the browser tabs of the
/// same origin (Web Locks API). Outside a browser there is none: [action]
/// runs at once.
Future<T> syncedDbSharedLock<T>(String name, Future<T> Function() action) =>
    action();
