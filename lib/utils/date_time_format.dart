String formatDateTime(DateTime dateTime) {
  String twoDigits(int value) => value.toString().padLeft(2, '0');

  return '${dateTime.year}-${twoDigits(dateTime.month)}-'
      '${twoDigits(dateTime.day)} ${twoDigits(dateTime.hour)}:'
      '${twoDigits(dateTime.minute)}';
}
