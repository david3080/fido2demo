import 'package:dart_dpop/dart_dpop.dart';

Future<void> main() async {
  // 1. 起動時に key pair を生成 (or 永続化済み seed から復元)
  final key = await Es256DpopKey.generate();
  final generator = DpopProofGenerator(key: key);

  // 2. token endpoint への request
  final tokenProof = await generator.createProof(
    htm: 'POST',
    htu: 'https://op.example.com/token',
  );
  print('DPoP for token endpoint:');
  print(tokenProof);

  // 3. resource access 時 (access_token の ath claim 付き)
  const accessToken = 'eyJhbGciOi... (received from token endpoint)';
  final apiProof = await generator.createProof(
    htm: 'GET',
    htu: 'https://api.example.com/me',
    accessToken: accessToken,
  );
  print('\nDPoP for resource access:');
  print(apiProof);

  // 4. JKT thumbprint (= 公開鍵 ID、access_token の cnf.jkt と照合できる)
  print('\nJKT: ${await key.jkt}');
}
