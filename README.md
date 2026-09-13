<p align="center">
  <img src="screenshots/overview.png" alt="PatKit package illustration" width="180">
</p>

# PatKit

PatKit is a pure Dart codec for Adobe Photoshop pattern libraries (`.pat`). It decodes and encodes the original source planes and metadata, renders portable RGBA previews, and preserves extensions that are not yet understood. It has no Flutter, native-code, or third-party PAT-parser dependency.

The package is intended for editors such as Focale that need dependable access to more than thumbnails: exact pattern identifiers, full-precision channels, indexed palettes, transparency, group hierarchy, and bounded decoding of untrusted files.

## Supported data

- Standalone `8BPT` version 1 libraries with any number of unframed pattern records.
- Photoshop bitmap, grayscale, indexed, RGB, CMYK, multichannel, duotone, and Lab color modes.
- Raw and row-based PackBits channels at 1, 8, 16, and 32 bits per sample.
- Signed source bounds, sparse channel slots, user masks, and sheet-transparency channels.
- Interleaved 256-entry indexed palettes, color-count metadata, and transparent palette indices.
- Version 16 `phry` Action Descriptors with nested groups, group ends, presets, names, and identifiers.
- Unknown color modes, compression markers, channel bytes, descriptor values, and tagged blocks preserved for forward compatibility.
- Configurable limits for file size, records, dimensions, channels, compressed data, decoded pixels, descriptors, hierarchy entries, and tagged blocks.
- Canonical PAT writing from decoded raw or PackBits planes, including indexed metadata, hierarchy descriptors, and optional compatibility data.

## Usage

```dart
import 'dart:io';
import 'dart:typed_data';

import 'package:patkit/patkit.dart';

final Uint8List bytes = await File('patterns.pat').readAsBytes();
final PatFile library = PatDecoder.decode(bytes);

for (final PatPattern pattern in library.patterns) {
  final PatPatternImage image = pattern.renderRgba8();
  print('${pattern.name}: ${image.width} × ${image.height} (${pattern.id})');
}

final Uint8List output = PatEncoder.encode(library);
await File('patterns-copy.pat').writeAsBytes(output, flush: true);
```

`PatPatternImage.rgba` contains four bytes per pixel in red, green, blue, alpha order. Source channels remain available through `PatPattern.channels`; their `sampleAt`, `normalizedSampleAt`, and `byteSampleAt` methods retain the distinctions between 1, 8, 16, and floating-point 32-bit data. Check `pattern.canRenderRgba8` when decoding was disabled or an unsupported channel was preserved; `renderRgba8` rejects unavailable planes instead of silently returning a misleading preview.

Indexed patterns expose `palette` and `indexedMetadata`. CMYK rendering accepts an application-provided color converter when the host has an ICC workflow:

```dart
final PatPatternImage image = pattern.renderRgba8(
  cmykConverter: ({required cyan, required magenta, required yellow, required black}) {
    return convertWithApplicationProfile(cyan, magenta, yellow, black);
  },
);
```

Without a converter, PatKit returns a deterministic profile-free preview. Lab is converted through D50 XYZ to sRGB. Multichannel and duotone sources use their first plane as a grayscale preview because their external ink definitions are not stored in the PAT record.

## Reusable `dart:convert` API

`PatCodec` implements `Codec<PatFile, List<int>>` and keeps decoding and encoding policies together in one immutable value:

```dart
const PatCodec codec = PatCodec(
  decodeOptions: PatDecodeOptions(mode: PatDecodeMode.strict),
  encodeOptions: PatEncodeOptions(mode: PatEncodeMode.strict),
);

final PatFile library = codec.decode(bytes);
final Uint8List output = codec.encode(library);
```

The `List<int>` binary type allows composition with standard codecs such as `base64`; direct `encode` calls still return `Uint8List`. `PatEncoder` and `PatDecoder` are also configurable `Converter` implementations. Every conversion consumes or produces one complete in-memory PAT file rather than an incremental byte stream.

## Hierarchy

Newer Photoshop files can append a `phry` hierarchy. `PatFile.hierarchy` is a flattened ordered sequence of group starts, group ends, and presets. Preset entries resolve directly to their source pattern:

```dart
for (final PatHierarchyEntry entry in library.hierarchy) {
  final PatPattern? pattern = library.patternFor(entry);
  if (pattern != null) {
    print('${'  ' * entry.depth}${pattern.name}');
  }
}
```

The complete generic `PsDescriptor` is also retained for every hierarchy block.

## Decoding and encoding policies

Tolerant decoding is the default. Recoverable extensions are preserved and reported through `PatFile.warnings`. Strict mode turns each compatibility warning into a `PatFormatException`:

```dart
final PatFile library = PatDecoder.decode(
  bytes,
  options: const PatDecodeOptions(mode: PatDecodeMode.strict),
);
```

The preservation switches are independent:

- `decodeChannelData` controls decompression;
- `preserveChannelData` retains encoded channel payloads;
- `preserveRecordData` retains each complete pattern record;
- `preserveTaggedBlockData` retains trailing tagged payloads.

For an editor that only needs rendered pixels, keep `decodeChannelData` enabled and disable the three preservation switches to avoid redundant source copies. All configured resource limits are checked before the corresponding allocation.

`PatEncoder.encode` writes a canonical standalone version 1 library by default. Known channel planes are rebuilt from decoded samples with their selected raw or PackBits compression, so `preserveChannelData` and `preserveRecordData` can be disabled when channel decoding remains enabled. Indexed palettes and metadata, sparse slots, tagged blocks, and hierarchy descriptors are included.

Permissive mode reproduces representable compatibility values and preserved extension bytes:

```dart
final Uint8List output = PatEncoder.encode(
  library,
  options: const PatEncodeOptions(mode: PatEncodeMode.permissive),
);
```

Unknown channel encodings and opaque tagged blocks require their source payloads to have been preserved. Invalid or incomplete models produce a `PatWriteException` instead of partial output.

## Scope

PatKit reads, writes, and previews PAT files. It does not apply ICC color profiles or interpret the external ink definitions needed for exact multichannel and duotone compositing; applications can provide their own CMYK conversion for previews. Focale integration is intentionally left to a separate change.

See [docs/PAT.md](docs/PAT.md) for the implemented binary layout, compatibility matrix, and rendering conventions.

## References

- [Adobe Photoshop File Formats Specification](https://www.adobe.com/devnet-apps/photoshop/fileformatashtml/)
- [psd-tools pattern structures](https://github.com/psd-tools/psd-tools/blob/main/src/psd_tools/psd/patterns.py)
- [Patchy PAT compatibility notes](https://github.com/SethRobinson/Patchy/blob/main/docs/ps-compat.md)
- [Patchy pattern decoder](https://github.com/SethRobinson/Patchy/blob/main/src/psd/psd_patterns.cpp)
- [pat-parser](https://github.com/jardicc/pat-parser)

PatKit is an independent implementation and is not affiliated with or endorsed by Adobe.

---

Built for **[Focale](https://focale-editor.app)**, an advanced local image editor. Discover what these packages make possible in a real creative workflow.
