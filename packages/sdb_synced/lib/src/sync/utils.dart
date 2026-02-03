/// For deleted/dirty fields
int boolToInt(bool? value) {
  return (value ?? false) ? 1 : 0;
}

/// For deleted/dirty fields
bool intToBool(int? value) {
  return (value ?? 0) != 0;
}
