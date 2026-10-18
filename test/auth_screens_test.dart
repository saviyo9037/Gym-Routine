import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/core/theme.dart';
import 'package:reptrack/screens/account_switch_screen.dart';
import 'package:reptrack/screens/auth_flow_screen.dart';
import 'package:reptrack/screens/forgot_password_screen.dart';
import 'package:reptrack/screens/login_screen.dart';
import 'package:reptrack/screens/not_configured_screen.dart';
import 'package:reptrack/screens/register_screen.dart';
import 'package:reptrack/screens/reset_password_screen.dart';
import 'package:reptrack/screens/verify_email_screen.dart';
import 'package:reptrack/services/account_switch.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/cloud_services.dart';
import 'package:reptrack/services/premium_service.dart';

import 'helpers/scripted_auth.dart';
import 'helpers/test_db.dart';

Future<void> settle(WidgetTester tester) async {
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 30)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Widget host(Widget child, {double scale = 1.0}) => MaterialApp(
  theme: AppTheme.darkTheme,
  builder: (c, w) => MediaQuery(
    data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
    child: w!,
  ),
  home: child,
);

void useSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.reset);
}

const strongPassword = 'Gr0undSquat!';

Future<void> typeInto(WidgetTester tester, Key key, String text) async {
  await tester.enterText(find.byKey(key), text);
  await tester.pump();
}

void main() {
  late ScriptedAuthService auth;

  setUp(() {
    mockPlatformPlugins();
    ignoreMissingPluginErrors();
    CloudServices.resetForTesting();
    auth = ScriptedAuthService();
    CloudServices.auth = auth;
    CloudServices.accountSwitch = AccountSwitch(store: MemorySettingsStore());
  });

  tearDown(CloudServices.resetForTesting);

  group('MOCK-ONLY: register', () {
    Future<void> pumpRegister(
      WidgetTester tester, {
      void Function(String)? onVerify,
      VoidCallback? onSignedIn,
      void Function(String)? onLogin,
      double scale = 1.0,
    }) async {
      useSize(tester, const Size(800, 1800));
      await tester.pumpWidget(
        host(
          RegisterScreen(
            onLogin: onLogin ?? (_) {},
            onNeedsVerification: onVerify ?? (_) {},
            onSignedIn: onSignedIn,
          ),
          scale: scale,
        ),
      );
      await settle(tester);
    }

    Future<void> fill(
      WidgetTester tester, {
      String email = 'new@example.com',
      String password = strongPassword,
      String? confirm,
      bool terms = true,
    }) async {
      await typeInto(tester, const ValueKey('auth_email'), email);
      await typeInto(tester, const ValueKey('auth_new_password'), password);
      await typeInto(
        tester,
        const ValueKey('auth_confirm_password'),
        confirm ?? password,
      );
      if (terms) {
        await tester.tap(find.byKey(const ValueKey('auth_terms')));
        await tester.pump();
      }
    }

    testWidgets('strength meter and rule checklist update live', (
      tester,
    ) async {
      await pumpRegister(tester);
      expect(find.text('Choose a strong password'), findsOneWidget);
      await typeInto(tester, const ValueKey('auth_new_password'), 'abc');
      expect(find.text('Strength: Too short'), findsOneWidget);
      expect(
        find.bySemanticsLabel('At least 10 characters: not met'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel('A lowercase letter: met'), findsOneWidget);
      await typeInto(
        tester,
        const ValueKey('auth_new_password'),
        strongPassword,
      );
      expect(find.text('Strength: Strong'), findsOneWidget);
      expect(
        find.bySemanticsLabel('At least 10 characters: met'),
        findsOneWidget,
      );
    });

    testWidgets('weak or common password, mismatch and missing terms block', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fill(tester, password: 'short', terms: false);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(
        find.text('The password does not meet all the rules yet'),
        findsOneWidget,
      );
      expect(
        find.text('You need to accept to create an account.'),
        findsOneWidget,
      );
      expect(auth.calls, isEmpty);

      await fill(tester, password: 'Password123', confirm: 'Password123');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.text('That password is too easy to guess'), findsOneWidget);

      await fill(tester, password: strongPassword, confirm: 'Different1Pass');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.text('The passwords do not match'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('invalid e-mail is rejected before any request', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fill(tester, email: 'not-an-email');
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.text('Enter a valid e-mail'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('success with e-mail confirmation goes to verification', (
      tester,
    ) async {
      String? verifyEmail;
      await pumpRegister(tester, onVerify: (e) => verifyEmail = e);
      await fill(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(auth.calls, ['signUp']);
      expect(verifyEmail, 'new@example.com');
    });

    testWidgets('success without confirmation signs in', (tester) async {
      auth.signUpNeedsConfirmation = false;
      var signedIn = false;
      await pumpRegister(tester, onSignedIn: () => signedIn = true);
      await fill(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(auth.isSignedIn, isTrue);
      expect(signedIn, isTrue);
    });

    testWidgets('existing e-mail shows the message and a sign-in shortcut', (
      tester,
    ) async {
      auth.registered.add('new@example.com');
      String? loginEmail;
      await pumpRegister(tester, onLogin: (e) => loginEmail = e);
      await fill(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.textContaining('already exists'), findsOneWidget);
      await tester.tap(find.text('Sign in instead'));
      await settle(tester);
      expect(loginEmail, 'new@example.com');
    });

    testWidgets('network down and rate limited show their own message', (
      tester,
    ) async {
      await pumpRegister(tester);
      await fill(tester);
      auth.nextFailure = const AuthFailure(
        'Could not reach the server. Check your connection and try again.',
        kind: AuthFailureKind.network,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);

      auth.nextFailure = const AuthFailure(
        'Too many attempts. Please wait a few minutes and try again.',
        kind: AuthFailureKind.rateLimited,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      expect(find.textContaining('Could not reach the server'), findsNothing);
    });

    testWidgets('no double submit while a request is running', (tester) async {
      final gate = Completer<void>();
      final slow = _SlowSignUp(gate.future);
      CloudServices.auth = slow;
      await pumpRegister(tester);
      await fill(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await tester.pump();
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      await tester.tap(find.byType(ElevatedButton), warnIfMissed: false);
      await tester.pump();
      expect(slow.calls.where((c) => c == 'signUp').length, 1);
      gate.complete();
      await settle(tester);
    });

    testWidgets('fields expose autofill hints and accessible toggles', (
      tester,
    ) async {
      await pumpRegister(tester);
      final email = tester.widget<TextFormField>(
        find.byKey(const ValueKey('auth_email')),
      );
      expect(email.autovalidateMode, isNotNull);
      expect(find.byTooltip('Show password'), findsNWidgets(2));
      await tester.tap(find.byTooltip('Show password').first);
      await tester.pump();
      expect(find.byTooltip('Hide password'), findsOneWidget);
      expect(find.byType(AutofillGroup), findsOneWidget);
    });
  });

  group('MOCK-ONLY: login', () {
    Future<void> pumpLogin(
      WidgetTester tester, {
      void Function(String)? onVerify,
      VoidCallback? onSignedIn,
      void Function(String)? onForgot,
      VoidCallback? onRegister,
    }) async {
      useSize(tester, const Size(800, 1800));
      await tester.pumpWidget(
        host(
          LoginScreen(
            onRegister: onRegister ?? () {},
            onForgot: onForgot ?? (_) {},
            onNeedsVerification: onVerify ?? (_) {},
            onSignedIn: onSignedIn,
          ),
        ),
      );
      await settle(tester);
    }

    Future<void> submit(
      WidgetTester tester, {
      String email = 'me@example.com',
      String password = 'whatever1',
    }) async {
      await typeInto(tester, const ValueKey('auth_email'), email);
      await typeInto(tester, const ValueKey('auth_password'), password);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
    }

    testWidgets('empty fields are validated first', (tester) async {
      await pumpLogin(tester);
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
      expect(find.text('Enter your e-mail'), findsOneWidget);
      expect(find.text('Enter your password'), findsOneWidget);
      expect(auth.calls, isEmpty);
    });

    testWidgets('wrong password, network down, rate limited, then success', (
      tester,
    ) async {
      var signedIn = false;
      await pumpLogin(tester, onSignedIn: () => signedIn = true);

      auth.nextFailure = const AuthFailure(
        'The e-mail or password is not correct.',
        kind: AuthFailureKind.wrongCredentials,
      );
      await submit(tester);
      expect(
        find.text('The e-mail or password is not correct.'),
        findsOneWidget,
      );

      auth.nextFailure = const AuthFailure(
        'Could not reach the server. Check your connection and try again.',
        kind: AuthFailureKind.network,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
      expect(find.textContaining('Could not reach the server'), findsOneWidget);
      expect(find.text('The e-mail or password is not correct.'), findsNothing);

      auth.nextFailure = const AuthFailure(
        'Too many attempts. Please wait a few minutes and try again.',
        kind: AuthFailureKind.rateLimited,
      );
      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
      expect(find.textContaining('Too many attempts'), findsOneWidget);

      await tester.tap(find.widgetWithText(ElevatedButton, 'Sign in'));
      await settle(tester);
      expect(auth.isSignedIn, isTrue);
      expect(signedIn, isTrue);
    });

    testWidgets('unverified e-mail hands over to the verification screen', (
      tester,
    ) async {
      String? verifyEmail;
      await pumpLogin(tester, onVerify: (e) => verifyEmail = e);
      auth.nextFailure = const AuthFailure(
        'Please confirm your e-mail first.',
        kind: AuthFailureKind.emailNotConfirmed,
      );
      await submit(tester);
      expect(verifyEmail, 'me@example.com');
    });

    testWidgets('forgot password passes the typed e-mail along', (
      tester,
    ) async {
      String? forgotEmail;
      await pumpLogin(tester, onForgot: (e) => forgotEmail = e);
      await typeInto(tester, const ValueKey('auth_email'), 'me@example.com');
      await tester.tap(find.text('Forgot password?'));
      await settle(tester);
      expect(forgotEmail, 'me@example.com');
    });

    testWidgets('Google button appears only when Google is configured', (
      tester,
    ) async {
      await pumpLogin(tester);
      expect(find.text('Continue with Google'), findsNothing);
      auth.google = true;
      await pumpLogin(tester);
      await tester.pumpAndSettle(const Duration(milliseconds: 100));
      expect(find.text('Continue with Google'), findsOneWidget);
      await tester.tap(find.text('Continue with Google'));
      await settle(tester);
      expect(auth.calls, contains('google'));
      expect(auth.isSignedIn, isTrue);
    });

    testWidgets('a cancelled Google sign-in shows no error', (tester) async {
      auth.google = true;
      await pumpLogin(tester);
      auth.nextFailure = const AuthFailure(
        'Sign-in was cancelled.',
        kind: AuthFailureKind.cancelled,
      );
      await tester.tap(find.text('Continue with Google'));
      await settle(tester);
      expect(find.text('Sign-in was cancelled.'), findsNothing);
    });

    testWidgets('locked options stay reachable on the sign-in screen', (
      tester,
    ) async {
      await pumpLogin(tester);
      expect(find.text('Restore purchases'), findsOneWidget);
      expect(find.text('Manage subscription'), findsOneWidget);
      expect(find.text('Export my data'), findsOneWidget);
    });
  });

  group('MOCK-ONLY: forgot password', () {
    testWidgets('sends the reset mail, then shows the sent state', (
      tester,
    ) async {
      useSize(tester, const Size(800, 1800));
      var back = false;
      await tester.pumpWidget(
        host(
          ForgotPasswordScreen(
            initialEmail: 'me@example.com',
            onBack: () => back = true,
          ),
        ),
      );
      await settle(tester);
      await tester.tap(find.text('Send reset link'));
      await settle(tester);
      expect(auth.calls, ['reset']);
      expect(find.textContaining('a reset link is on its'), findsOneWidget);
      await tester.tap(find.text('Back to sign in'));
      await settle(tester);
      expect(back, isTrue);
    });

    testWidgets('validates the e-mail and surfaces rate limiting', (
      tester,
    ) async {
      useSize(tester, const Size(800, 1800));
      await tester.pumpWidget(host(ForgotPasswordScreen(onBack: () {})));
      await settle(tester);
      await tester.tap(find.text('Send reset link'));
      await settle(tester);
      expect(find.text('Enter your e-mail'), findsOneWidget);
      expect(auth.calls, isEmpty);

      await typeInto(tester, const ValueKey('auth_email'), 'me@example.com');
      auth.nextFailure = const AuthFailure(
        'Too many attempts. Please wait a few minutes and try again.',
        kind: AuthFailureKind.rateLimited,
      );
      await tester.tap(find.text('Send reset link'));
      await settle(tester);
      expect(find.textContaining('Too many attempts'), findsOneWidget);
    });
  });

  group('MOCK-ONLY: verify e-mail', () {
    Future<void> pumpVerify(
      WidgetTester tester, {
      void Function(String)? onSignIn,
      Duration cooldown = const Duration(seconds: 3),
    }) async {
      useSize(tester, const Size(800, 1800));
      await tester.pumpWidget(
        host(
          VerifyEmailScreen(
            email: 'new@example.com',
            cooldown: cooldown,
            onSignIn: onSignIn ?? (_) {},
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('resend is blocked during the cooldown, then works', (
      tester,
    ) async {
      await pumpVerify(tester);
      expect(find.text('Resend e-mail in 3s'), findsOneWidget);
      await tester.tap(find.text('Resend e-mail in 3s'), warnIfMissed: false);
      await tester.pump();
      expect(auth.calls, isEmpty);

      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Resend e-mail in 2s'), findsOneWidget);
      await tester.pump(const Duration(seconds: 3));
      expect(find.text('Resend e-mail'), findsOneWidget);

      await tester.tap(find.text('Resend e-mail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(auth.calls, ['resend']);
      expect(
        find.text('A new confirmation e-mail is on its way.'),
        findsOneWidget,
      );
      expect(find.textContaining('Resend e-mail in'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5)); // let the timer finish
    });

    testWidgets('a rate-limited resend restarts the cooldown', (tester) async {
      await pumpVerify(tester, cooldown: const Duration(seconds: 2));
      await tester.pump(const Duration(seconds: 3));
      auth.nextFailure = const AuthFailure(
        'Too many attempts. Please wait a few minutes and try again.',
        kind: AuthFailureKind.rateLimited,
      );
      await tester.tap(find.text('Resend e-mail'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.textContaining('Too many attempts'), findsOneWidget);
      expect(find.textContaining('Resend e-mail in'), findsOneWidget);
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets("'I've confirmed it' (signed out) returns to sign-in", (
      tester,
    ) async {
      String? email;
      await pumpVerify(tester, onSignIn: (e) => email = e);
      await tester.tap(find.text("I've confirmed it - sign in"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(email, 'new@example.com');
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('signed in but unverified: refresh says not yet, then passes', (
      tester,
    ) async {
      auth.setUser(
        const CloudUser(
          id: 'u-1',
          email: 'new@example.com',
          emailVerified: false,
        ),
      );
      await pumpVerify(tester);
      await tester.tap(find.text("I've confirmed it"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Your e-mail is not confirmed yet.'), findsOneWidget);

      auth.confirmOnRefresh = true;
      await tester.tap(find.text("I've confirmed it"));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(auth.user!.emailVerified, isTrue);
      expect(find.text('Your e-mail is not confirmed yet.'), findsNothing);
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('MOCK-ONLY: reset password (recovery link)', () {
    testWidgets('rules, mismatch, then the new password is saved', (
      tester,
    ) async {
      useSize(tester, const Size(800, 1800));
      auth.setUser(const CloudUser(id: 'u-1', email: 'me@example.com'));
      auth.startRecovery();
      var done = false;
      await tester.pumpWidget(
        host(ResetPasswordScreen(onDone: () => done = true)),
      );
      await settle(tester);

      await typeInto(tester, const ValueKey('auth_reset_password'), 'weak');
      await typeInto(tester, const ValueKey('auth_reset_confirm'), 'weak');
      await tester.tap(find.text('Save new password'));
      await settle(tester);
      expect(
        find.text('The password does not meet all the rules yet'),
        findsOneWidget,
      );
      expect(auth.calls, isNot(contains('updatePassword')));

      await typeInto(
        tester,
        const ValueKey('auth_reset_password'),
        strongPassword,
      );
      await typeInto(
        tester,
        const ValueKey('auth_reset_confirm'),
        'Nope12345!x',
      );
      await tester.tap(find.text('Save new password'));
      await settle(tester);
      expect(find.text('The passwords do not match'), findsOneWidget);

      await typeInto(
        tester,
        const ValueKey('auth_reset_confirm'),
        strongPassword,
      );
      await tester.tap(find.text('Save new password'));
      await settle(tester);
      expect(auth.lastPasswordSet, strongPassword);
      expect(auth.recoveryPending, isFalse);
      expect(done, isTrue);
    });
  });

  group('MOCK-ONLY: auth flow navigation', () {
    testWidgets('login -> register -> verify -> sign-in with e-mail kept', (
      tester,
    ) async {
      useSize(tester, const Size(800, 1800));
      await tester.pumpWidget(
        host(const AuthFlowScreen(verifyCooldown: Duration(seconds: 1))),
      );
      await settle(tester);
      expect(find.text('Welcome back'), findsOneWidget);

      await tester.tap(find.textContaining('Create an account'));
      await settle(tester);
      expect(find.text('Create your account'), findsOneWidget);

      await typeInto(tester, const ValueKey('auth_email'), 'new@example.com');
      await typeInto(
        tester,
        const ValueKey('auth_new_password'),
        strongPassword,
      );
      await typeInto(
        tester,
        const ValueKey('auth_confirm_password'),
        strongPassword,
      );
      await tester.tap(find.byKey(const ValueKey('auth_terms')));
      await tester.pump();
      await tester.tap(find.widgetWithText(ElevatedButton, 'Create account'));
      await settle(tester);
      expect(find.text('Check your inbox'), findsOneWidget);
      expect(find.textContaining('new@example.com'), findsWidgets);

      await tester.tap(find.text("I've confirmed it - sign in"));
      await settle(tester);
      expect(find.text('Welcome back'), findsOneWidget);
      final email = tester.widget<TextFormField>(
        find.byKey(const ValueKey('auth_email')),
      );
      expect(email.controller!.text, 'new@example.com');
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('MOCK-ONLY: account switch screen', () {
    Future<void> pumpSwitch(
      WidgetTester tester,
      VoidCallback onResolved,
    ) async {
      useSize(tester, const Size(800, 1800));
      await tester.pumpWidget(
        host(AccountSwitchScreen(onResolved: onResolved)),
      );
      await settle(tester);
    }

    testWidgets('cancel signs out and nothing is linked', (tester) async {
      auth.setUser(const CloudUser(id: 'u-B', email: 'b@example.com'));
      var resolved = false;
      await pumpSwitch(tester, () => resolved = true);
      expect(
        find.text('This phone belongs to another account'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel and sign out'));
      await settle(tester);
      expect(auth.calls, contains('signOut'));
      expect(resolved, isFalse);
    });
  });

  group('MOCK-ONLY: cloud not configured', () {
    testWidgets('every auth screen renders the not-configured state', (
      tester,
    ) async {
      useSize(tester, const Size(800, 1800));
      CloudServices.auth = NoCloudAuthService();
      for (final screen in <Widget>[
        const AuthFlowScreen(),
        LoginScreen(
          onRegister: () {},
          onForgot: (_) {},
          onNeedsVerification: (_) {},
        ),
        RegisterScreen(onLogin: (_) {}, onNeedsVerification: (_) {}),
        ForgotPasswordScreen(onBack: () {}),
        const NotConfiguredScreen(),
      ]) {
        await tester.pumpWidget(host(screen));
        await settle(tester);
        expect(
          find.text('This build is not connected to RepTrack accounts'),
          findsOneWidget,
        );
        expect(find.byType(TextFormField), findsNothing);
        expect(find.text('Export my data'), findsOneWidget);
        expect(tester.takeException(), isNull);
      }
    });
  });

  group('MOCK-ONLY: layout (360x640, text 1.0x and 2.0x)', () {
    final screens = <String, Widget Function()>{
      'login': () => LoginScreen(
        onRegister: () {},
        onForgot: (_) {},
        onNeedsVerification: (_) {},
      ),
      'register': () =>
          RegisterScreen(onLogin: (_) {}, onNeedsVerification: (_) {}),
      'forgot': () => ForgotPasswordScreen(onBack: () {}),
      'verify': () => VerifyEmailScreen(
        email: 'a-rather-long-address-for-layout-testing@example-domain.com',
        cooldown: Duration.zero,
        onSignIn: (_) {},
      ),
      'reset': () => const ResetPasswordScreen(),
      'switch': () => AccountSwitchScreen(onResolved: () {}),
      'not configured': () => const NotConfiguredScreen(),
    };
    for (final scale in const [1.0, 2.0]) {
      for (final e in screens.entries) {
        testWidgets('${e.key} at text x$scale', (tester) async {
          useSize(tester, const Size(360, 640));
          auth.google = true;
          auth.setUser(const CloudUser(id: 'u-1', email: 'me@example.com'));
          if (e.key != 'reset' && e.key != 'switch' && e.key != 'verify') {
            auth.setUser(null);
          }
          await tester.pumpWidget(host(e.value(), scale: scale));
          await settle(tester);
          expect(tester.takeException(), isNull);
        });
      }
    }

    testWidgets(
      'register at x2.0: scrolling to the end and submitting an invalid form',
      (tester) async {
        useSize(tester, const Size(360, 640));
        await tester.pumpWidget(
          host(
            RegisterScreen(onLogin: (_) {}, onNeedsVerification: (_) {}),
            scale: 2.0,
          ),
        );
        await settle(tester);
        final button = find.widgetWithText(ElevatedButton, 'Create account');
        await tester.dragUntilVisible(
          button,
          find.byType(ListView),
          const Offset(0, -200),
        );
        await tester.tap(button);
        await settle(tester);
        expect(
          find.text('You need to accept to create an account.'),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);
      },
    );
  });
}

class _SlowSignUp extends ScriptedAuthService {
  _SlowSignUp(this._gate);
  final Future<void> _gate;

  @override
  Future<bool> signUpWithEmail(String email, String password) async {
    calls.add('signUp');
    await _gate;
    return true;
  }
}
