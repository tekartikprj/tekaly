import 'package:cv/cv.dart';

/// Api response
class ApiErrorResponse extends CvModelBase {
  /// Response code
  late final code = CvField<String>('code');

  /// Message
  late final message = CvField<String>('message');

  /// stackTrace
  late final stackTrace = CvField<String>('stackTrace');

  @override
  late final List<CvField<Object?>> fields = [code, message, stackTrace];
}
