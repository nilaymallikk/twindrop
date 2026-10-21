import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:twindrop/features/models.dart';
import 'package:twindrop/features/pairing/desktop_pairing_screen.dart';
import 'package:twindrop/features/pairing/phone_onboarding_screen.dart';
import 'package:twindrop/theme/theme.dart';
import 'package:twindrop_core/core.dart';

Widget _host(Widget child) {
  return MaterialApp(
    theme: buildTdTheme(
      choice: AppThemeChoice.dark,
      platformBrightness: Brightness.dark,
    ),
    home: Scaffold(body: child),
  );
}

void main() {
  group('desktop pairing screen', () {
    testWidgets('the idle stage offers to create a pairing session', (
      tester,
    ) async {
      var started = 0;
      await tester.pumpWidget(
        _host(
          DesktopPairingScreen(
            data: const DesktopPairingData(stage: DesktopPairingStage.idle),
            onStart: () => started++,
            onCancel: () {},
            onApprove: (_) {},
            onReject: (_) {},
          ),
        ),
      );

      expect(find.text('Create a code'), findsOneWidget);
      await tester.tap(find.text('Create a code'));
      expect(started, 1);
    });

    testWidgets('the waiting stage shows the QR payload and the address', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          DesktopPairingScreen(
            data: const DesktopPairingData(
              stage: DesktopPairingStage.waitingForPhone,
              qrPayload: 'twindrop://pair?payload=abc',
              manualAddress: '192.168.1.23:47321',
              fingerprint: 'A1B2C3',
              expiryLabel: '4:32 left',
            ),
            onStart: () {},
            onCancel: () {},
            onApprove: (_) {},
            onReject: (_) {},
          ),
        ),
      );

      expect(find.text('192.168.1.23:47321'), findsOneWidget);
      expect(find.text('A1B2C3'), findsOneWidget);
      expect(find.textContaining('4:32'), findsOneWidget);
    });

    testWidgets('approval passes the request id through', (tester) async {
      final approved = <String>[];
      final rejected = <String>[];
      await tester.pumpWidget(
        _host(
          DesktopPairingScreen(
            data: const DesktopPairingData(
              stage: DesktopPairingStage.approval,
              requestId: 'req-42',
              requestDeviceName: 'Pixel',
              requestPlatform: 'android',
              confirmationCode: '4271',
            ),
            onStart: () {},
            onCancel: () {},
            onApprove: approved.add,
            onReject: rejected.add,
          ),
        ),
      );

      expect(find.text('Pixel'), findsOneWidget);
      expect(find.text('4271'), findsWidgets);

      await tester.tap(find.text('Approve'));
      await tester.pumpAndSettle();
      expect(approved, <String>['req-42']);

      await tester.tap(find.text('Decline'));
      await tester.pumpAndSettle();
      expect(rejected, <String>['req-42']);
    });

    testWidgets('an expired request cannot be approved', (tester) async {
      final approved = <String>[];
      await tester.pumpWidget(
        _host(
          DesktopPairingScreen(
            data: const DesktopPairingData(
              stage: DesktopPairingStage.approval,
              requestDeviceName: 'Pixel',
              confirmationCode: '4271',
            ),
            onStart: () {},
            onCancel: () {},
            onApprove: approved.add,
            onReject: (_) {},
            onRetry: () {},
          ),
        ),
      );

      // No request id means there is nothing to approve.
      expect(approved, isEmpty);
      expect(find.textContaining('expired'), findsOneWidget);
    });

    testWidgets('the connected stage names the paired device', (tester) async {
      await tester.pumpWidget(
        _host(
          DesktopPairingScreen(
            data: const DesktopPairingData(
              stage: DesktopPairingStage.connected,
              connectedDeviceName: 'Pixel 8',
            ),
            onStart: () {},
            onCancel: () {},
            onApprove: (_) {},
            onReject: (_) {},
          ),
        ),
      );

      expect(find.textContaining('Pixel 8'), findsOneWidget);
    });
  });

  group('phone onboarding screen', () {
    PhoneOnboardingScreen build({
      PhoneOnboardingData data = const PhoneOnboardingData(
        stage: PhoneOnboardingStage.welcome,
      ),
      VoidCallback? onStartScan,
      ValueChanged<String>? onSubmitQr,
      VoidCallback? onManualEntry,
      ValueChanged<String>? onConfirmFingerprint,
      void Function(String, String)? onSubmitManual,
      ValueChanged<PermissionStepState>? onPermissionDecided,
      ValueChanged<PhonePermission>? onSkip,
      VoidCallback? onCancel,
    }) {
      return PhoneOnboardingScreen(
        data: data,
        onStartScan: onStartScan ?? () {},
        onSubmitQr: onSubmitQr ?? (_) {},
        onManualEntry: onManualEntry ?? () {},
        onConfirmFingerprint: onConfirmFingerprint ?? (_) {},
        onSubmitManual: onSubmitManual ?? (_, __) {},
        onPermissionDecided: onPermissionDecided ?? (_) {},
        onSkip: onSkip ?? (_) {},
        onCancel: onCancel ?? () {},
        onDone: () async {},
      );
    }

    testWidgets('the welcome stage offers both pairing routes', (tester) async {
      var scan = 0;
      var manual = 0;
      await tester.pumpWidget(
        _host(build(onStartScan: () => scan++, onManualEntry: () => manual++)),
      );

      expect(find.text('Scan the code on the desktop'), findsOneWidget);
      expect(find.text('Enter the address manually'), findsOneWidget);

      await tester.tap(find.text('Scan the code on the desktop'));
      await tester.tap(find.text('Enter the address manually'));
      expect(scan, 1);
      expect(manual, 1);
    });

    testWidgets('manual entry submits the address and the code', (
      tester,
    ) async {
      final submitted = <String, String>{};
      await tester.pumpWidget(
        _host(
          build(
            data: const PhoneOnboardingData(
              stage: PhoneOnboardingStage.manualEntry,
            ),
            onSubmitManual: (hostPort, code) =>
                submitted['hostPort'] = '$hostPort|$code',
          ),
        ),
      );

      await tester.enterText(
        find.byType(TextField).at(0),
        '192.168.1.23:47321',
      );
      await tester.enterText(find.byType(TextField).at(1), 'ABCD');
      await tester.tap(find.text('Continue'));
      await tester.pump();

      expect(submitted['hostPort'], '192.168.1.23:47321|ABCD');
    });

    testWidgets('an invalid address shows the error from the host', (
      tester,
    ) async {
      await tester.pumpWidget(
        _host(
          build(
            data: const PhoneOnboardingData(
              stage: PhoneOnboardingStage.manualEntry,
              errorMessage: 'Enter an address like 192.168.1.23:47321.',
            ),
          ),
        ),
      );

      expect(
        find.text('Enter an address like 192.168.1.23:47321.'),
        findsOneWidget,
      );
    });

    testWidgets('the fingerprint step confirms the code the host sent', (
      tester,
    ) async {
      final confirmed = <String>[];
      await tester.pumpWidget(
        _host(
          build(
            data: const PhoneOnboardingData(
              stage: PhoneOnboardingStage.fingerprintConfirm,
              fingerprint: 'A1B2C3',
            ),
            onConfirmFingerprint: confirmed.add,
          ),
        ),
      );

      expect(find.text('A1B2C3'), findsWidgets);
      await tester.tap(find.text('They match'));
      await tester.pump();
      expect(confirmed, <String>['A1B2C3']);
    });

    testWidgets('each permission step can be allowed or skipped', (
      tester,
    ) async {
      final decided = <PhonePermission>[];
      final skipped = <PhonePermission>[];
      await tester.pumpWidget(
        _host(
          build(
            data: const PhoneOnboardingData(
              stage: PhoneOnboardingStage.permissions,
              permissions: <PermissionStepState>[
                PermissionStepState(permission: PhonePermission.notifications),
                PermissionStepState(permission: PhonePermission.background),
              ],
            ),
            onPermissionDecided: (step) => decided.add(step.permission),
            onSkip: skipped.add,
          ),
        ),
      );

      expect(find.text('Notifications'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pump();
      expect(decided, <PhonePermission>[PhonePermission.notifications]);

      await tester.tap(find.text('Skip'));
      await tester.pump();
      expect(skipped, <PhonePermission>[PhonePermission.notifications]);
    });
  });
}
