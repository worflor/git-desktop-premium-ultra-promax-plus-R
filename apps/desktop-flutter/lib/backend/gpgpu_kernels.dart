// Concrete GPGPU kernels. Each one implements [GpgpuKernel] for a
// specific operation and acts as a reference for how to plug new
// compute kernels into the [runGpgpuKernel] harness.
//
// No kernels currently ship — the harness primitives in `gpgpu.dart`
// (encodeFloat32Texture, runGpgpuKernel, decodeFloat32Output) are
// usable, but any concrete kernel must:
//   1. ship a compatible `.frag` under `shaders/`,
//   2. register that shader path in `pubspec.yaml`'s `shaders:` list,
//   3. subclass [GpgpuKernel] with its asset / outputSize /
//      packInputs / decodeOutput overrides.
//
// The worked-example `GpgpuTanhKernel` was removed after its shader
// (`gpgpu_tanh.frag`) couldn't compile under Impeller SkSL — SkSL
// lacks the `uintBitsToFloat` / `floatBitsToUint` bit-cast primitives
// the bit-pack round-trip depends on. Future kernels that fit within
// SkSL's subset (arithmetic, sampler reads, arithmetic transcendentals)
// can follow the same shape.
