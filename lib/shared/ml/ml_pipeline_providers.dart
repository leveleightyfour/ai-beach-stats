import 'package:riverpod_annotation/riverpod_annotation.dart';

import 'ml_pipeline_facade.dart';

part 'ml_pipeline_providers.g.dart';

@Riverpod(keepAlive: true)
MLPipelineFacade mlPipelineFacade(MlPipelineFacadeRef ref) {
  return MLPipelineFacade();
}
