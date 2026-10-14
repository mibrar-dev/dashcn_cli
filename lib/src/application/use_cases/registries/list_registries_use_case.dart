import 'package:dashcn_cli/src/core/result/result.dart';

class ListRegistriesUseCase {
  Future<AppResult<List<String>>> call() async {
    return const AppResult.success(<String>[]);
  }
}
