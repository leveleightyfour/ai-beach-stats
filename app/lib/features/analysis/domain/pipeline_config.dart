import '../../../core/constants/pipeline_defaults.dart';

class PipelineConfig {
  const PipelineConfig({
    this.frameRateHz = PipelineDefaults.frameRateHz,
    this.rallyGapThresholdSeconds = PipelineDefaults.rallyGapThresholdSeconds,
    this.minRallyDurationSeconds = PipelineDefaults.minRallyDurationSeconds,
    this.touchProximityPx = PipelineDefaults.touchProximityPx,
    this.detectionConfidenceThreshold =
        PipelineDefaults.detectionConfidenceThreshold,
  });

  final int frameRateHz;
  final double rallyGapThresholdSeconds;
  final double minRallyDurationSeconds;
  final double touchProximityPx;
  final double detectionConfidenceThreshold;
}
