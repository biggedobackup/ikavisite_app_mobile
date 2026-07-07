int? _toInt(dynamic val) => (val as num?)?.toInt();

class DashboardStats {
  final DashboardPeriod period;
  final List<StatItem> stats;
  final List<BarChartItem> visitsByDepartment;
  final List<BarChartItem> visitsByDay;
  final List<BarChartItem> visitsByEntryPoint;
  final List<BarChartItem> incidentsFlow;
  final List<PieChartItem> visitTypes;
  final int totalVisitesParType;
  final bool showChartVisitsByDepartment;
  final bool showChartVisitsByDay;
  final bool showChartVisitsByEntryPoint;
  final bool showChartIncidentsFlow;
  final bool showChartVisitTypes;

  DashboardStats({
    required this.period,
    required this.stats,
    required this.visitsByDepartment,
    required this.visitsByDay,
    required this.visitsByEntryPoint,
    required this.incidentsFlow,
    required this.visitTypes,
    required this.totalVisitesParType,
    this.showChartVisitsByDepartment = true,
    this.showChartVisitsByDay = true,
    this.showChartVisitsByEntryPoint = true,
    this.showChartIncidentsFlow = true,
    this.showChartVisitTypes = true,
  });

  factory DashboardStats.fromJson(Map<String, dynamic> json) {
    return DashboardStats(
      period: DashboardPeriod.fromJson(json['period'] as Map<String, dynamic>),
      stats: (json['stats'] as List)
          .map((e) => StatItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      visitsByDepartment: (json['visits_by_department'] as List)
          .map((e) => BarChartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      visitsByDay: (json['visits_by_day'] as List)
          .map((e) => BarChartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      visitsByEntryPoint: (json['visits_by_entry_point'] as List)
          .map((e) => BarChartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      incidentsFlow: (json['incidents_flow'] as List)
          .map((e) => BarChartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      visitTypes: (json['visit_types'] as List)
          .map((e) => PieChartItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      totalVisitesParType: _toInt(json['total_visites_par_type']) ?? 0,
      showChartVisitsByDepartment: json['show_chart_departments'] as bool? ?? true,
      showChartVisitsByDay: json['show_chart_weekday'] as bool? ?? true,
      showChartVisitsByEntryPoint: json['show_chart_entry_points'] as bool? ?? true,
      showChartIncidentsFlow: json['show_chart_incidents'] as bool? ?? true,
      showChartVisitTypes: json['show_chart_visit_types'] as bool? ?? true,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'period': period.toJson(),
      'stats': stats.map((e) => e.toJson()).toList(),
      'visits_by_department': visitsByDepartment.map((e) => e.toJson()).toList(),
      'visits_by_day': visitsByDay.map((e) => e.toJson()).toList(),
      'visits_by_entry_point': visitsByEntryPoint.map((e) => e.toJson()).toList(),
      'incidents_flow': incidentsFlow.map((e) => e.toJson()).toList(),
      'visit_types': visitTypes.map((e) => e.toChartJson()).toList(),
      'total_visites_par_type': totalVisitesParType,
      'show_chart_departments': showChartVisitsByDepartment,
      'show_chart_weekday': showChartVisitsByDay,
      'show_chart_entry_points': showChartVisitsByEntryPoint,
      'show_chart_incidents': showChartIncidentsFlow,
      'show_chart_visit_types': showChartVisitTypes,
    };
  }

  Map<String, dynamic> toMap() {
    return {
      'stats_json': toJson(),
    };
  }

  factory DashboardStats.fromMap(Map<String, dynamic> map) {
    return DashboardStats.fromJson(
        map['stats_json'] as Map<String, dynamic>);
  }
}

class DashboardPeriod {
  final String label;
  final String start;
  final String end;

  DashboardPeriod({
    required this.label,
    required this.start,
    required this.end,
  });

  factory DashboardPeriod.fromJson(Map<String, dynamic> json) {
    return DashboardPeriod(
      label: json['label'] as String? ?? '',
      start: json['start'] as String? ?? '',
      end: json['end'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'start': start,
      'end': end,
    };
  }
}

class StatItem {
  final String icon;
  final String tone;
  final String label;
  final int value;
  final String sub;
  final String? screen;

  StatItem({
    required this.icon,
    required this.tone,
    required this.label,
    required this.value,
    required this.sub,
    this.screen,
  });

  factory StatItem.fromJson(Map<String, dynamic> json) {
    return StatItem(
      icon: json['icon'] as String? ?? '',
      tone: json['tone'] as String? ?? '',
      label: json['label'] as String? ?? '',
      value: _toInt(json['value']) ?? 0,
      sub: json['sub'] as String? ?? '',
      screen: json['screen'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'icon': icon,
      'tone': tone,
      'label': label,
      'value': value,
      'sub': sub,
      if (screen != null) 'screen': screen,
    };
  }
}

class BarChartItem {
  final String label;
  final int value;
  final int? width;
  final int? height;
  final String? day;

  BarChartItem({
    required this.label,
    required this.value,
    this.width,
    this.height,
    this.day,
  });

  factory BarChartItem.fromJson(Map<String, dynamic> json) {
    return BarChartItem(
      label: json['label'] as String? ?? json['day'] as String? ?? '',
      value: _toInt(json['value']) ?? 0,
      width: _toInt(json['width']),
      height: _toInt(json['height']),
      day: json['day'] as String?,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'value': value,
      if (width != null) 'width': width,
      if (height != null) 'height': height,
      if (day != null) 'day': day,
    };
  }
}

class PieChartItem {
  final String label;
  final int value;
  final String color;

  PieChartItem({
    required this.label,
    required this.value,
    required this.color,
  });

  factory PieChartItem.fromJson(Map<String, dynamic> json) {
    return PieChartItem(
      label: json['label'] as String? ?? '',
      value: _toInt(json['value']) ?? 0,
      color: json['color'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'label': label,
      'value': value,
      'color': color,
    };
  }

  Map<String, dynamic> toChartJson() {
    return toJson();
  }
}
