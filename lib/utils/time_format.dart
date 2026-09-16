// Parses a 12-hour time string like "3:51 PM" or "3:51PM" into today's date
// at that time, or null if the string is empty or malformed.
DateTime? parseTimeString(String timeStr) {
  if (timeStr.isEmpty) return null;

  try {
    final now = DateTime.now();
    final cleanTime = timeStr.replaceAll(' ', '').toUpperCase();
    final isPM = cleanTime.contains('PM');
    final isAM = cleanTime.contains('AM');

    final timePart = cleanTime.replaceAll('PM', '').replaceAll('AM', '');
    final parts = timePart.split(':');

    if (parts.length != 2) return null;

    int hour = int.parse(parts[0]);
    final minute = int.parse(parts[1]);

    if (isPM && hour != 12) {
      hour += 12;
    } else if (isAM && hour == 12) {
      hour = 0;
    }

    return DateTime(now.year, now.month, now.day, hour, minute);
  } catch (e) {
    return null;
  }
}
