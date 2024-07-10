import 'package:cv/cv.dart';

class ApiErrorResponse extends CvModelBase {
  late final code = CvField<String>('code');
  // Never expires unless forced
  late final message = CvField<String>('message');
  late final stackTrace = CvField<String>('stackTrace');

  @override
  late final List<CvField<Object?>> fields = [code, message, stackTrace];
}
