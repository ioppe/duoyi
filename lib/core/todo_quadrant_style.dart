import 'package:flutter/painting.dart';

import '../models/todo.dart';
import 'design_tokens.dart';

/// 四象限在不同页面使用同一套语义配色。
Color todoQuadrantColor(EisenhowerQuadrant quadrant) => switch (quadrant) {
  EisenhowerQuadrant.urgentImportant => DesignTokens.quadrantQ1,
  EisenhowerQuadrant.notUrgentImportant => DesignTokens.quadrantQ2,
  EisenhowerQuadrant.urgentNotImportant => DesignTokens.quadrantQ3,
  EisenhowerQuadrant.notUrgentNotImportant => DesignTokens.quadrantQ4,
};
