/// A non-fatal validation finding. Conversion still produces output.
class ValidationMessage {
  final int line;
  final String message;

  const ValidationMessage({
    required this.line,
    required this.message,
  });
}
