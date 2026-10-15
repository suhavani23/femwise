/// Clearly labelled sample records, kept in a separate encrypted dataset.
class DemoTrackingData {
  static String day(DateTime value) =>
      '${value.year}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';

  static Map<String, dynamic> create(DateTime now) {
    final today = DateTime(now.year, now.month, now.day);
    final latestStart = today.subtract(const Duration(days: 10));
    final starts = [latestStart];
    for (final gap in [42, 35, 46, 31]) {
      starts.add(starts.last.subtract(Duration(days: gap)));
    }
    final logs = <String, dynamic>{};
    for (var cycle = 0; cycle < starts.length; cycle++) {
      for (var offset = 0; offset < 4 + cycle % 3; offset++) {
        final date = day(starts[cycle].add(Duration(days: offset)));
        logs[date] = {
          'date': date,
          'isDemo': true,
          'isOnPeriod': true,
          'menstrualDay': offset + 1,
          'periodFlow': offset < 2 ? 'Medium' : 'Light',
          'mood': offset == 0 ? 'Low' : 'Neutral',
          'symptoms': {
            'fatigue': offset < 2,
            'cramps': offset == 0,
            'headache': false,
            'acne': false,
            'bloating': offset < 2
          },
          'cervicalMucus': 'N/A',
          'opkResult': 'N/A',
          'intercourseToday': false,
          'notes':
              'DEMO: Sample irregular cycle ${starts.length - cycle}. Not a real health record.',
        };
      }
      final date = day(starts[cycle].add(const Duration(days: 15)));
      if (date.compareTo(day(today)) < 0)
        logs[date] = {
          'date': date,
          'isDemo': true,
          'isOnPeriod': false,
          'mood': 'Neutral',
          'symptoms': {},
          'periodFlow': 'None',
          'cervicalMucus': 'Dry',
          'opkResult': 'Negative',
          'intercourseToday': false,
          'notes':
              'DEMO: Sample day between periods. Cycle lengths vary in this dataset.',
        };
    }
    return {
      'profile': {
        'name': 'Demo',
        'isDemo': true,
        'onboardingComplete': true,
        'lastPeriodStartDate': day(latestStart),
        'typicalCycleLength': 39,
        'averagePeriodDuration': 5,
        'currentCycleStatus': 'NOT_PERIOD'
      },
      'logs': logs,
    };
  }
}
