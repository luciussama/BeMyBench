import 'package:bemybench/features/cleaner/cleaner_models.dart';
import 'package:bemybench/features/cleaner/cleaner_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('formatBytes formata corretamente diferentes ordens de grandeza', () {
    expect(CategoryScanResult.formatBytes(512), '512 B');
    expect(CategoryScanResult.formatBytes(2048), '2.0 KB');
    expect(CategoryScanResult.formatBytes(15 * 1024 * 1024), '15.0 MB');
    expect(CategoryScanResult.formatBytes(2 * 1024 * 1024 * 1024), '2.00 GB');
  });

  test('scanDisk executa varredura segura sem erros e retorna categorias', () async {
    final service = CleanerService();
    final report = await service.scanDisk();

    expect(report.categories, isNotEmpty);
    expect(report.categories.length, CleanCategoryType.values.length);
    expect(report.durationMs, greaterThanOrEqualTo(0));
    expect(report.totalBytes, greaterThanOrEqualTo(0));
  });

  test('boostRam executa purga e retorna relatório estruturado', () async {
    final service = CleanerService();
    final boost = await service.boostRam();

    expect(boost.isSuccess, isTrue);
    expect(boost.methodUsed, isNotEmpty);
    expect(boost.durationMs, greaterThanOrEqualTo(0));
    expect(boost.ramTotalBytes, greaterThanOrEqualTo(0));
  });
}
