import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:reptrack/services/auth_service.dart';
import 'package:reptrack/services/password_rules.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  group('mapAuthError (pure, real Supabase exception types)', () {
    AuthFailureKind kindOf(Object e) => mapAuthError(e).kind;

    test('wrong password / unknown account', () {
      expect(
        kindOf(
          const AuthApiException(
            'Invalid login credentials',
            statusCode: '400',
            code: 'invalid_credentials',
          ),
        ),
        AuthFailureKind.wrongCredentials,
      );
      expect(
        kindOf(const AuthException('Invalid login credentials')),
        AuthFailureKind.wrongCredentials,
      );
    });

    test('e-mail not confirmed', () {
      expect(
        kindOf(
          const AuthApiException(
            'Email not confirmed',
            statusCode: '400',
            code: 'email_not_confirmed',
          ),
        ),
        AuthFailureKind.emailNotConfirmed,
      );
    });

    test('e-mail already registered (both codes and the old text)', () {
      for (final code in ['user_already_exists', 'email_exists']) {
        expect(
          kindOf(AuthApiException('x', statusCode: '422', code: code)),
          AuthFailureKind.emailTaken,
        );
      }
      expect(
        kindOf(const AuthException('User already registered')),
        AuthFailureKind.emailTaken,
      );
    });

    test('weak password', () {
      expect(
        kindOf(
          const AuthApiException(
            'Password should be at least 6 characters',
            statusCode: '422',
            code: 'weak_password',
          ),
        ),
        AuthFailureKind.weakPassword,
      );
    });

    test('rate limited (e-mail limit, request limit, HTTP 429)', () {
      expect(
        kindOf(
          const AuthApiException(
            'email rate limit exceeded',
            statusCode: '429',
            code: 'over_email_send_rate_limit',
          ),
        ),
        AuthFailureKind.rateLimited,
      );
      expect(
        kindOf(
          const AuthApiException(
            'x',
            statusCode: '429',
            code: 'over_request_rate_limit',
          ),
        ),
        AuthFailureKind.rateLimited,
      );
      expect(
        kindOf(const AuthException('slow down', statusCode: '429')),
        AuthFailureKind.rateLimited,
      );
    });

    test('invalid e-mail', () {
      expect(
        kindOf(
          const AuthApiException(
            'Unable to validate email address: invalid format',
            statusCode: '400',
            code: 'validation_failed',
          ),
        ),
        AuthFailureKind.invalidEmail,
      );
    });

    test('network down in all its shapes', () {
      expect(
        kindOf(AuthRetryableFetchException(message: 'offline')),
        AuthFailureKind.network,
      );
      expect(
        kindOf(const SocketException('no route')),
        AuthFailureKind.network,
      );
      expect(kindOf(TimeoutException('slow')), AuthFailureKind.network);
      expect(kindOf(Exception('anything else')), AuthFailureKind.network);
    });

    test('server error and unknown auth error', () {
      expect(
        kindOf(const AuthException('boom', statusCode: '503')),
        AuthFailureKind.server,
      );
      expect(
        kindOf(const AuthApiException('???', statusCode: '400', code: 'zzz')),
        AuthFailureKind.unknown,
      );
    });

    test('an AuthFailure passes through unchanged', () {
      const f = AuthFailure('hello', kind: AuthFailureKind.cancelled);
      expect(identical(mapAuthError(f), f), isTrue);
    });

    test('messages never echo the e-mail, password or tokens', () {
      const secrets = ['person@example.com', 'Sup3rSecret!', 'eyJhbGciOi'];
      for (final e in [
        AuthApiException(
          'Invalid login credentials for person@example.com Sup3rSecret! eyJhbGciOi',
          statusCode: '400',
          code: 'invalid_credentials',
        ),
        AuthApiException(
          'person@example.com already registered',
          statusCode: '422',
          code: 'user_already_exists',
        ),
        AuthException('weird person@example.com eyJhbGciOi', statusCode: '400'),
      ]) {
        final text = mapAuthError(e).message;
        for (final s in secrets) {
          expect(text.contains(s), isFalse, reason: text);
        }
      }
    });
  });

  group('PasswordRules (pure)', () {
    test('checklist reflects each requirement', () {
      final c = PasswordRules.checklist('abc');
      expect(c.map((r) => r.ok), [false, true, false, false]);
      final full = PasswordRules.checklist('Abcdefghi1');
      expect(full.every((r) => r.ok), isTrue);
    });

    test('rules: length 10, lower, upper, digit; symbol optional', () {
      expect(PasswordRules.meetsRules('Abcdefgh1'), isFalse); // 9 chars
      expect(PasswordRules.meetsRules('abcdefghi1'), isFalse); // no upper
      expect(PasswordRules.meetsRules('ABCDEFGHI1'), isFalse); // no lower
      expect(PasswordRules.meetsRules('Abcdefghij'), isFalse); // no digit
      expect(PasswordRules.meetsRules('Abcdefghi1'), isTrue);
      expect(PasswordRules.meetsRules('Abcdefgh1!'), isTrue);
    });

    test('common passwords and the e-mail name are rejected', () {
      expect(PasswordRules.isCommon('Password123'), isTrue);
      expect(PasswordRules.meetsRules('Password123'), isFalse);
      expect(
        PasswordRules.meetsRules(
          'Johnsmith2026',
          email: 'johnsmith@example.com',
        ),
        isFalse,
      );
      expect(
        PasswordRules.meetsRules('Tr0ub4dour-Gym', email: 'johnsmith@x.com'),
        isTrue,
      );
    });

    test('validate gives field messages', () {
      expect(PasswordRules.validate(''), 'Enter a password');
      expect(PasswordRules.validate('short'), contains('rules'));
      expect(PasswordRules.validate('Password123'), contains('easy to guess'));
      expect(PasswordRules.validate('Gr0undSquat!'), isNull);
    });

    test('strength meter 0..4 is monotone with effort', () {
      expect(PasswordRules.strength(''), 0);
      expect(PasswordRules.strength('abc'), 0);
      expect(PasswordRules.strength('Password123'), 1);
      final fair = PasswordRules.strength('Abcdefghij');
      final good = PasswordRules.strength('Abcdefghi1');
      final strong = PasswordRules.strength('Abcdefghi1!xyz');
      expect(fair <= good, isTrue);
      expect(good <= strong, isTrue);
      expect(strong, 4);
      expect(PasswordRules.strengthLabel(0), 'Too short');
      expect(PasswordRules.strengthLabel(4), 'Strong');
    });

    test('e-mail validation', () {
      expect(PasswordRules.validEmail('a@b.co'), isTrue);
      expect(PasswordRules.validEmail(' a@b.co '), isTrue);
      expect(PasswordRules.validEmail('a@b'), isFalse);
      expect(PasswordRules.validEmail('a b@c.com'), isFalse);
      expect(PasswordRules.validEmail(''), isFalse);
      expect(PasswordRules.validEmail(null), isFalse);
    });
  });

  group('NoCloudAuthService (cloud not configured)', () {
    test('reports not configured and fails softly, never crashes', () async {
      final a = NoCloudAuthService();
      expect(a.isConfigured, isFalse);
      expect(a.isSignedIn, isFalse);
      expect(a.recoveryPending, isFalse);
      for (final call in <Future<void> Function()>[
        () => a.signInWithEmail('a@b.co', 'x'),
        () => a.signUpWithEmail('a@b.co', 'x'),
        () => a.resendConfirmation('a@b.co'),
        () => a.signInWithGoogle(),
        () => a.sendPasswordReset('a@b.co'),
        () => a.updatePassword('x'),
        () => a.deleteAccount(),
      ]) {
        await expectLater(
          call(),
          throwsA(
            isA<AuthFailure>().having(
              (f) => f.kind,
              'kind',
              AuthFailureKind.notConfigured,
            ),
          ),
        );
      }
      await a.signOut(); // harmless
      await a.refreshUser(); // harmless
    });
  });
}
