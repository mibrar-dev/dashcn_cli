import 'package:dashcn_cli/src/core/result/result.dart';

class SearchComponentsUseCase {
  Future<AppResult<List<String>>> call(String query) async {
    return const AppResult.success(<String>[]);
  }
}
