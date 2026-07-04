// Shared "which model produced this" attribution for LLM-output
// clipboard exports (muse, commit review, …).
//
// Every AI DTO records the provider + model that generated it. When the
// user copies that output, the identity should ride along in the dump —
// and it should read identically no matter which report renderer emitted
// it. Centralising the format here is the single knob that keeps the muse
// export, the review export, and any future report from drifting apart.

/// A single `provider / model` descriptor for one generation phase.
///
/// Returns `''` only when BOTH halves are blank (a hand-authored or
/// pre-attribution snapshot); otherwise renders whichever half is known,
/// so a partially-recorded identity still surfaces rather than showing a
/// dangling ` / ` or an empty slot.
String modelDescriptor(String providerId, String modelId) {
  final provider = providerId.trim();
  final model = modelId.trim();
  if (provider.isEmpty && model.isEmpty) return '';
  if (provider.isEmpty) return model;
  if (model.isEmpty) return provider;
  return '$provider / $model';
}

/// The `Model: provider / model` attribution line for a single-model
/// report, or `''` when no identity was recorded — so callers can skip
/// emitting a bare `Model:` header with nothing after it. Newline-free;
/// the caller owns line breaks.
String modelAttributionLine(String providerId, String modelId) {
  final descriptor = modelDescriptor(providerId, modelId);
  return descriptor.isEmpty ? '' : 'Model: $descriptor';
}
