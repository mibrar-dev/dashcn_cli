import 'package:dashcn_cli/src/core/result/result.dart';

class ChooseDefaultRegistryUseCase {
  Future<AppResult<String>> call() async {
    return const AppResult.success('dashcn');
  }
}
