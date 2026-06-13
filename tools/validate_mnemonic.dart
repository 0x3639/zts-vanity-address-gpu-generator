import 'dart:io';

import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Future<void> main(List<String> args) async {
  if (args.length < 24 || args.length > 25) {
    stderr.writeln(
      'Usage: dart run tools/validate_mnemonic.dart <24 seed words> [account_index]',
    );
    exit(64);
  }

  final hasAccountIndex = args.length == 25;
  final accountIndex = hasAccountIndex ? int.parse(args.last) : 0;
  final words = hasAccountIndex ? args.sublist(0, 24) : args;
  final mnemonic = words.join(' ');

  final store = KeyStore.fromMnemonic(mnemonic);
  final address = await store.getKeyPair(accountIndex).address;

  stdout.writeln(address.toString());
}
