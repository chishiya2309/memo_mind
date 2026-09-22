String greetingFor(DateTime time) {
  if (time.hour >= 5 && time.hour < 12) return 'Chào buổi sáng';
  if (time.hour >= 12 && time.hour < 18) return 'Chào buổi chiều';
  return 'Chào buổi tối';
}

String vietnameseDate(DateTime date) {
  const weekdays = [
    'Thứ Hai',
    'Thứ Ba',
    'Thứ Tư',
    'Thứ Năm',
    'Thứ Sáu',
    'Thứ Bảy',
    'Chủ Nhật',
  ];
  return '${weekdays[date.weekday - 1]}, ${date.day} tháng ${date.month}';
}

String importedDate(DateTime importedAt, DateTime now) {
  final imported = DateTime(importedAt.year, importedAt.month, importedAt.day);
  final today = DateTime(now.year, now.month, now.day);
  final days = today.difference(imported).inDays;
  if (days == 0) return 'hôm nay';
  if (days == 1) return 'hôm qua';
  return '${importedAt.day}/${importedAt.month}';
}
