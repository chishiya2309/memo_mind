import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

bool _initialized = false;

tz.Location statisticsTimeZone(String identifier) {
  if (!_initialized) {
    tzdata.initializeTimeZones();
    _initialized = true;
  }
  return tz.getLocation(identifier);
}

Future<String> deviceStatisticsTimeZone() async =>
    (await FlutterTimezone.getLocalTimezone()).identifier;
