/// Password rules for new accounts, shown live while typing.
///
/// Required: at least [minLength] characters, a lowercase letter, an
/// uppercase letter and a digit, and not an obviously common password or
/// the e-mail name. A symbol and extra length only raise the strength meter.
class PasswordRules {
  static const int minLength = 10;

  static const _common = {
    'password',
    'password1',
    'password123',
    'passw0rd',
    '1234567890',
    '12345678910',
    'qwertyuiop',
    'qwerty12345',
    'iloveyou123',
    'welcome123',
    'letmein123',
    'admin12345',
    'reptrack123',
  };

  static bool hasLength(String p) => p.length >= minLength;
  static bool hasLower(String p) => RegExp(r'[a-z]').hasMatch(p);
  static bool hasUpper(String p) => RegExp(r'[A-Z]').hasMatch(p);
  static bool hasDigit(String p) => RegExp(r'[0-9]').hasMatch(p);
  static bool hasSymbol(String p) => RegExp(r'[^A-Za-z0-9]').hasMatch(p);

  static bool isCommon(String p, {String? email}) {
    final l = p.toLowerCase();
    if (_common.contains(l)) return true;
    final name = (email ?? '').split('@').first.toLowerCase();
    return name.length >= 4 && l.contains(name);
  }

  /// The four required rules, in display order.
  static List<({String label, bool ok})> checklist(String p) => [
    (label: 'At least $minLength characters', ok: hasLength(p)),
    (label: 'A lowercase letter', ok: hasLower(p)),
    (label: 'An uppercase letter', ok: hasUpper(p)),
    (label: 'A number', ok: hasDigit(p)),
  ];

  static bool meetsRules(String p, {String? email}) =>
      hasLength(p) &&
      hasLower(p) &&
      hasUpper(p) &&
      hasDigit(p) &&
      !isCommon(p, email: email);

  /// null when acceptable, otherwise a short message for the form field.
  static String? validate(String? p, {String? email}) {
    final v = p ?? '';
    if (v.isEmpty) return 'Enter a password';
    if (!meetsRules(v, email: email)) {
      if (isCommon(v, email: email)) {
        return 'That password is too easy to guess';
      }
      return 'The password does not meet all the rules yet';
    }
    return null;
  }

  /// 0 (empty/very weak) .. 4 (strong). Used for the meter and its label.
  static int strength(String p, {String? email}) {
    if (p.isEmpty) return 0;
    if (isCommon(p, email: email)) return 1;
    var score = 0;
    if (hasLength(p)) score++;
    if (hasLower(p) && hasUpper(p)) score++;
    if (hasDigit(p)) score++;
    if (hasSymbol(p) || p.length >= 14) score++;
    if (!hasLength(p) && score > 1) score = 1;
    return score.clamp(0, 4);
  }

  static String strengthLabel(int s) => switch (s) {
    0 => 'Too short',
    1 => 'Weak',
    2 => 'Fair',
    3 => 'Good',
    _ => 'Strong',
  };

  static bool validEmail(String? v) {
    final e = (v ?? '').trim();
    return RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]{2,}$').hasMatch(e);
  }
}
