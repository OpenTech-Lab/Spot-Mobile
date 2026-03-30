import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mobile/core/wallet.dart';
import 'package:mobile/models/wallet_model.dart';
import 'package:mobile/screens/session_gate_screen.dart';
import 'package:mobile/services/app_lock_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', (message) async => null);
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  testWidgets('saved wallet stays locked until unlock succeeds', (
    tester,
  ) async {
    final service = _FakeAppLockService(
      status: const AppLockStatus(
        canAuthenticate: true,
        message: 'Unlock this saved account.',
      ),
      authenticateResult: false,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGateScreen(
          initialWallet: _wallet(),
          appLockService: service,
          unlockedBuilder: (_) => const Text('Unlocked home'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Saved account locked'), findsOneWidget);
    expect(find.text('Unlocked home'), findsNothing);

    service.authenticateResult = true;
    await tester.ensureVisible(find.text('Unlock this account'));
    await tester.tap(find.text('Unlock this account'));
    await tester.pumpAndSettle();

    expect(find.text('Unlocked home'), findsOneWidget);
    expect(find.text('Saved account locked'), findsNothing);
  });

  testWidgets('reset from lock screen clears the saved account', (
    tester,
  ) async {
    var logoutCalls = 0;
    final service = _FakeAppLockService(
      status: const AppLockStatus(
        canAuthenticate: false,
        message: 'Reset required.',
      ),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGateScreen(
          initialWallet: _wallet(),
          appLockService: service,
          logoutRunner: () async => logoutCalls++,
          onboardingBuilder: () => const Text('Onboarding flow'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Saved account locked'), findsOneWidget);
    expect(find.text('Unlock this account'), findsNothing);

    await tester.ensureVisible(find.text('This is not my account'));
    await tester.tap(find.text('This is not my account'));
    await tester.pumpAndSettle();

    expect(logoutCalls, 1);
    expect(find.text('Onboarding flow'), findsOneWidget);
  });

  testWidgets('recovery phrase can unlock the saved account', (tester) async {
    final service = _FakeAppLockService(
      status: const AppLockStatus(
        canAuthenticate: false,
        message: 'Reset required.',
      ),
    );
    final wallet = _wallet();

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGateScreen(
          initialWallet: wallet,
          appLockService: service,
          unlockedBuilder: (_) => const Text('Unlocked home'),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('Unlock with recovery phrase'), findsOneWidget);

    await tester.tap(find.text('Unlock with recovery phrase'));
    await tester.pumpAndSettle();

    expect(find.text('Unlock with recovery phrase'), findsWidgets);
    await tester.enterText(
      find.byKey(const Key('recovery_phrase_unlock_field')),
      wallet.mnemonic.join(' '),
    );
    await tester.tap(find.text('Unlock').last);
    await tester.pumpAndSettle();

    expect(find.text('Unlocked home'), findsOneWidget);
    expect(find.text('Saved account locked'), findsNothing);
  });

  testWidgets('resume after timeout re-locks the saved account', (
    tester,
  ) async {
    final service = _FakeAppLockService(
      status: const AppLockStatus(
        canAuthenticate: true,
        message: 'Unlock this saved account.',
      ),
      authenticateResult: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        home: SessionGateScreen(
          initialWallet: _wallet(),
          appLockService: service,
          relockAfter: Duration.zero,
          unlockedBuilder: (_) => const Text('Unlocked home'),
        ),
      ),
    );

    await tester.pumpAndSettle();
    expect(find.text('Unlocked home'), findsOneWidget);

    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await tester.pumpAndSettle();

    expect(find.text('Saved account locked'), findsOneWidget);
    expect(find.text('Unlocked home'), findsNothing);
  });
}

class _FakeAppLockService extends AppLockService {
  _FakeAppLockService({required this.status, this.authenticateResult = false});

  final AppLockStatus status;
  bool authenticateResult;

  @override
  Future<AppLockStatus> getStatus() async => status;

  @override
  Future<bool> authenticate() async => authenticateResult;
}

WalletModel _wallet() => WalletModel(
  privateKeyHex: _walletKeypair.$1,
  publicKeyHex: _walletKeypair.$2,
  npub: 'npub1test',
  mnemonic: _mnemonic,
  deviceId: 'device-1',
  isRevoked: false,
  createdAt: DateTime.utc(2026, 3, 29),
);

const List<String> _mnemonic = [
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'abandon',
  'about',
];

final (String, String) _walletKeypair = WalletService.keypairFromMnemonic(
  _mnemonic,
);
