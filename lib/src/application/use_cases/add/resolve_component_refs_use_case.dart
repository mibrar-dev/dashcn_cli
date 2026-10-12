import 'package:dashcn_cli/src/core/result/result.dart';

class ResolveComponentRefsUseCase {
  Future<AppResult<List<String>>> call(List<String> tokens) async {
    return AppResult.success(tokens);
  }
}
