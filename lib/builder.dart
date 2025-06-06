import 'dart:convert';
import 'dart:io';

import 'package:build/build.dart';
import 'package:glob/glob.dart';
import 'package:path/path.dart' as p;

Builder buildStylesheet(BuilderOptions options) => TailwindBuilder(options);

class TailwindBuilder implements Builder {
  final BuilderOptions options;

  TailwindBuilder(this.options);

  @override
  Future<void> build(BuildStep buildStep) async {
    var outputId =
        buildStep.inputId.changeExtension('').changeExtension('.css');

    var packageFile = File('.dart_tool/package_config.json');
    var packageJson = jsonDecode(await packageFile.readAsString());

    var packageConfig = (packageJson['packages'] as List?)
        ?.where((p) => p['name'] == 'jaspr_tailwind')
        .firstOrNull;
    if (packageConfig == null) {
      print("Cannot find 'jaspr_tailwind' in package config.");
      return;
    }

    // in order to rebuild when source files change
    var assets = await buildStep.findAssets(Glob('{lib,web}/**.dart')).toList();
    await Future.wait(assets.map((a) => buildStep.canRead(a)));

    var configFile = File('tailwind.config.js');
    var hasCustomConfig = await configFile.exists();

    final runTailwind = await Process.run(
      'tailwindcss',
      [
        '--input',
        buildStep.inputId.path,
        if (options.config.containsKey('tailwindcss'))
          options.config['tailwindcss'],
        if (hasCustomConfig) ...[
          '--config',
          p.join(Directory.current.path, 'tailwind.config.js').toPosix(),
        ] else ...[
          '--content',
          p
              .join(Directory.current.path, '{lib,web}', '**', '*.dart')
              .toPosix(true),
        ],
      ],
      stdoutEncoding: Utf8Codec(),
      stderrEncoding: Utf8Codec(),
      runInShell: true,
    );

    final stderrLines = runTailwind.stderr.toString().trim().split('\n');
    final lastLine = stderrLines.isNotEmpty ? stderrLines.last : '';
    if (lastLine.contains('Done')) {
      log.info(runTailwind.stderr);
      final cssFileContent = runTailwind.stdout;
      await buildStep.writeAsString(outputId, cssFileContent);
    } else {
      log.severe(runTailwind.stderr);
    }
  }

  @override
  Map<String, List<String>> get buildExtensions => {
        'web/{{file}}.tw.css': ['web/{{file}}.css']
      };
}

extension POSIXPath on String {
  String toPosix([bool quoted = false]) {
    if (Platform.isWindows) {
      final result = replaceAll('\\', '/');
      return quoted ? "'$result'" : result;
    }
    return this;
  }
}
