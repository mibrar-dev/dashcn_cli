import 'package:dashcn_cli/src/application/services/installer/pub_package_resolver.dart';

/// In-memory [PubCommandRunner] so tests never shell out to `flutter`.
class FakePubCommandRunner implements PubCommandRunner {
  final List<String> pubGets = [];
  final List<List<String>> pubAdds = [];
  final List<({String package, String path})> pubPathAdds = [];

  @override
  Future<void> pubGet(String projectRoot) async => pubGets.add(projectRoot);

  @override
  Future<void> pubAdd(String projectRoot, Iterable<String> packages) async {
    pubAdds.add(packages.toList());
  }

  @override
  Future<void> pubAddPath(
      String projectRoot, String package, String path) async {
    pubPathAdds.add((package: package, path: path));
  }
}
