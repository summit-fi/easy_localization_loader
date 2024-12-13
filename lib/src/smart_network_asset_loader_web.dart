import 'dart:convert';
import 'dart:html';
import 'dart:ui' as ui;
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:easy_localization_loader/src/smart_network_asset_loader.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:easy_logger/easy_logger.dart';

class SmartNetworkAssetLoader extends AssetLoader {
  final Function(String) localeUrl;
  final Duration timeout;
  final String assetsPath;
  final Duration localCacheDuration;

  SmartNetworkAssetLoader({
    required this.localeUrl,
    this.timeout = const Duration(seconds: 30),
    required this.assetsPath,
    this.localCacheDuration = const Duration(days: 1),
  });

  @override
  Future<Map<String, dynamic>> load(String localePath, ui.Locale locale) async {
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

  Future<bool> isInternetConnectionAvailable() async {
    final connectivityResult = await Connectivity().checkConnectivity();
    if (connectivityResult[0] == ConnectivityResult.none) {
      return false;
    } else {
      try {
        final result = window.navigator.onLine ?? false;
        return result;
      } catch (_) {
        return false;
      }
    }
  }

  Future<String> loadFromNetwork(String localeName) async {
    String url = localeUrl(localeName);
    url = url + '' + localeName + '.json'.withoutCache();

    try {
      final response =
          await Future.any([http.get(Uri.parse(url)), Future.delayed(timeout)]);

      if (response != null && response.statusCode == 200) {
        var content = utf8.decode(response.bodyBytes);
        if (json.decode(content) != null) {
          await saveTranslation(localeName, content);
          return content;
        }
      }
    } catch (e) {
      print(e.toString());
    }

    return '';
  }

  Future<bool> localTranslationExists(String localeName,
      {bool ignoreCacheDuration = false}) async {
    var translationFile = await getFileForLocale(localeName);

    if (translationFile != null) {
      return true;
    }

    return false;
  }

  Future<String> loadFromLocalFile(String localeName) async {
    return window.localStorage[localeName] ?? '';
  }

  Future<void> saveTranslation(String localeName, String content) async {
    window.localStorage[localeName] = content;
    print('saved');
  }

  Future<File?> getFileForLocale(String localeName) async {
    return null; // No file system access in Flutter web
  }
}
