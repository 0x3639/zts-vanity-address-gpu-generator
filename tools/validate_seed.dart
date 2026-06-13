import 'dart:io';

import 'package:znn_sdk_dart/znn_sdk_dart.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty || args.length > 2) {
    stderr.writeln('Usage: dart run tools/validate_seed.dart <seed_hex> [account_index]');
    exit(64);
  }

  final seedHex = args[0].toLowerCase();
  final accountIndex = args.length == 2 ? int.parse(args[1]) : 0;

  final store = KeyStore.fromSeed(seedHex);
  final address = await store.getKeyPair(accountIndex).address;

  stdout.writeln(address.toString());
}
