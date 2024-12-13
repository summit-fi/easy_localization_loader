import 'dart:convert';
import 'dart:ui';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:http/http.dart';
import 'package:path_provider/path_provider.dart' as paths;
import 'package:universal_io/io.dart';
import 'package:easy_logger/easy_logger.dart';

extension CacheInvalidator on String {
  String withoutCache() {
    return '$this?v=${DateTime.now().millisecondsSinceEpoch}';
  }
}

/// ```dart
/// SmartNetworkAssetLoader(
///           assetsPath: 'assets/translations',
///           localCacheDuration: Duration(days: 1),
///           localeUrl: (String localeName) => Constants.appLangUrl,
///           timeout: Duration(seconds: 30),
///         )
/// ```
class SmartNetworkAssetLoader extends AssetLoader {
  SmartNetworkAssetLoader({
    required this.localeUrl,
    this.timeout = const Duration(seconds: 30),
    required this.assetsPath,
    this.localCacheDuration = const Duration(days: 1),
  });

  final String Function(String) localeUrl;
  final Duration timeout;
  final String assetsPath;
  final Duration localCacheDuration;

  @override
  Future<Map<String, dynamic>> load(String path, Locale locale) async {
    final EasyLogger logger = EasyLogger(name: '🌎 Easy Localization');

    String string = '';

    // // try loading local previously-saved localization file
    // if (await localTranslationExists(locale.toString())) {
    //   string = await loadFromLocalFile(locale.toString());
    // }
    String assetString = '';
    final Map<String, dynamic> result = <String, dynamic>{};

    // Load from assets to another map
    if (assetString == '') {
      assetString = await rootBundle.loadString('$assetsPath/$locale.json');
      final Map<String, dynamic> assetMap =
          jsonDecode(assetString) as Map<String, dynamic>;
      if (assetMap.isNotEmpty) {
        logger.debug('Got ${assetMap.entries.length} keys from assets');
        result.addAll(assetMap);
      }
    }

    // no local or failed, check if internet and download the file
    if (string == '' && await isInternetConnectionAvailable()) {
      string = await loadFromNetwork(locale.toString());
    }

    // local cache duration was reached or no internet access but prefer local file to assets
    if (string == '' &&
        await localTranslationExists(
          locale.toString(),
          ignoreCacheDuration: true,
        )) {
      string = await loadFromLocalFile(locale.toString());
    }

    if (string.isNotEmpty) {
      final Map<String, dynamic> stringMap =
          json.decode(string) as Map<String, dynamic>;

      logger.debug('Got ${stringMap.entries.length} keys from network');

      result.addAll(stringMap);
    }

    // then returns the json file
    return result;
  }

  Future<bool> localeExists(String localePath) => Future<bool>.value(true);

  Future<bool> isInternetConnectionAvailable() async {
    final List<ConnectivityResult> connectivityResult =
        await Connectivity().checkConnectivity();
    if (connectivityResult[0] == ConnectivityResult.none) {
      return false;
    } else {
      try {
        final List<InternetAddress> result =
            await InternetAddress.lookup('google.com');
        if (result.isNotEmpty && result[0].rawAddress.isNotEmpty) {
          return true;
        }
      } on SocketException catch (_) {
        return false;
      }
    }

    return false;
  }

  Future<String> loadFromNetwork(String localeName) async {
    String url = localeUrl(localeName);

    url = '$url$localeName${'.json'.withoutCache()}';

    try {
      final Response? response = await Future.any(
        <Future<http.Response?>>[
          http.get(Uri.parse(url)),
          Future<Response?>.delayed(timeout),
        ],
      );

      if (response != null && response.statusCode == 200) {
        final String content = utf8.decode(response.bodyBytes);

        // check valid json before saving it
        if (json.decode(content) != null) {
          await saveTranslation(localeName, content);
          return content;
        }
      }
    } catch (e) {
      print(e);
    }

    return '';
  }

  Future<bool> localTranslationExists(
    String localeName, {
    bool ignoreCacheDuration = false,
  }) async {
    final File translationFile = await getFileForLocale(localeName);

    if (!translationFile.existsSync()) {
      return false;
    }

    // don't check file's age
    if (!ignoreCacheDuration) {
      final Duration difference =
          DateTime.now().difference(translationFile.lastModifiedSync());

      if (difference > localCacheDuration) {
        return false;
      }
    }

    return true;
  }

  Future<String> loadFromLocalFile(String localeName) async {
    return (await getFileForLocale(localeName)).readAsString();
  }

  Future<void> saveTranslation(String localeName, String content) async {
    final File file = File(await getFilenameForLocale(localeName));
    await file.create(recursive: true);
    await file.writeAsString(content);
    return print('saved');
  }

  Future<String> get _localPath async {
    final Directory directory = await paths.getTemporaryDirectory();

    return directory.path;
  }

  Future<String> getFilenameForLocale(String localeName) async {
    return '${await _localPath}/translations/$localeName.json';
  }

  Future<File> getFileForLocale(String localeName) async {
    return File(await getFilenameForLocale(localeName));
  }
}
