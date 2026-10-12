import 'package:dashcn_cli/src/core/result/result.dart';

class AddComponentsUseCase {
  Future<AppResult<void>> call(List<String> componentIds) async {
    return const AppResult.success(null);
  }
}
