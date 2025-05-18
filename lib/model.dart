class DetectionResult {
  final String label;
  final double confidence;
  final List<double> bbox;

  DetectionResult({
    required this.label,
    required this.confidence,
    required this.bbox,
  });

  factory DetectionResult.fromJson(Map<String, dynamic> json) {
    return DetectionResult(
      label: json['label'],
      confidence: json['confidence'],
      bbox: List<double>.from(json['bbox']),
    );
  }
}