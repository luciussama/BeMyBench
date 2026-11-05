import 'package:bemybench/features/storage/storage_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parseDf separa volumes e ignora pseudo-filesystems', () {
    const sample = '''Filesystem 1024-blocks      Used Available Capacity iused ifree %iused  Mounted on
/dev/disk3s1      244373432  112806360 130676072    47%    1342 4294966937    0%   /
devfs                    395       395         0   100%     656         0  100%   /dev
map auto_home              0         0         0   100%       0         0  100%   /Network/Servers
/dev/disk3s5    244373432   99000000 145000000    41%       0         0  100%   /System/Volumes/Data
/dev/disk4s1     976321432 512000000 460000000    53%       0         0  100%   /Volumes/Externo
''';

    final volumes = StorageService.parseDf(sample);

    expect(
      volumes.map((v) => v.mount).toList(),
      ['/', '/System/Volumes/Data', '/Volumes/Externo'],
    );
    expect(volumes.first.totalBytes, 244373432 * 1024);
    expect(volumes.first.freeBytes, 130676072 * 1024);
    expect(volumes.first.capacityPercent, 47);
    expect(volumes[1].label, 'Data');
    expect(volumes[2].label, 'Externo');
  });

  test('parseDf ignora cabeçalho e linhas inválidas', () {
    const sample = '''Filesystem 1024-blocks      Used Available Capacity Mounted on
linha quebrada
/dev/disk0s1          1000       500       500    50% /Volumes/USB
''';

    final volumes = StorageService.parseDf(sample);
    expect(volumes, hasLength(1));
    expect(volumes.first.mount, '/Volumes/USB');
    expect(volumes.first.capacityPercent, 50);
  });
}
