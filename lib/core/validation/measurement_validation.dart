String? numberError(String? value) {
  if (value == null ||
      !RegExp(r'^[0-9]{1,3}$').hasMatch(value) ||
      int.parse(value) < 1) {
    return 'Inserisci un intero da 1 a 999';
  }
  return null;
}

bool systolicHigh(num value) => value > 135;
bool diastolicHigh(num value) => value > 90;
bool pulseHigh(num value) => value > 100;
