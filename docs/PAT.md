# PAT implementation notes

This document records the format variants implemented by PatKit. Photoshop's standalone PAT container is only partially documented publicly, so the notes combine Adobe's shared pattern structures with behavior verified against independent readers and real Photoshop exports.

## Compatibility matrix

| Area | Supported variants | Typed interpretation | Exact preservation |
| --- | --- | --- | --- |
| Container | `8BPT`, version 1 | Header and declared pattern count | Trailing unknown bytes |
| Color model | Bitmap, grayscale, indexed, RGB, CMYK, multichannel, duotone, Lab | RGBA8 preview | Original numeric mode |
| Precision | 1, 8, 16, 32 bits | Exact samples and normalized access | Encoded payload |
| Compression | Raw (`0`), PackBits (`1`) | Row-major decoded bytes | Unknown compression bytes |
| Indexed color | 256 interleaved RGB entries | Color count and transparent index | Four-byte palette footer |
| Channels | Sparse Virtual Memory Array slots | Color, user mask, and alpha access | All declared slots |
| Hierarchy | Version 16 `8BIM/phry` descriptor | Groups, group ends, presets | Complete descriptor and tagged payload |

All structural integers and floating-point values are big-endian. Coordinates are signed and use inclusive top/left with exclusive bottom/right edges.

## File envelope

The standalone header is:

```text
char[4] signature       // "8BPT"
uint16  version         // 1
uint32  patternCount
```

Exactly `patternCount` records follow. Unlike embedded pattern blocks in PSD or ABR data, standalone records do not have an outer record length or four-byte alignment. Synchronization comes from the bounded Virtual Memory Array inside each record.

## Pattern record

Each record begins with:

```text
uint32  version         // 1
uint32  colorMode
int16   vertical        // normally tile height
int16   horizontal      // normally tile width
UnicodeString name      // uint32 UTF-16 code-unit count, often null-terminated
PascalString identifier // uint8 byte count, commonly a UUID
```

Terminal nulls are removed from the decoded name and identifier, while the exact identifier bytes remain available.

For indexed color mode (`2`), the identifier is followed by 768 bytes representing 256 interleaved red, green, and blue entries. Standalone files normally append two unsigned 16-bit values: the meaningful color count and the transparent palette index. Embedded variants sometimes use four reserved bytes or omit the footer; the shared codec detects those layouts without shifting the following data.

## Virtual Memory Array

The remainder of a standalone record is bounded by:

```text
uint32 version          // 3
uint32 payloadLength
byte[payloadLength] payload
```

The payload starts with:

```text
int32  top
int32  left
int32  bottom
int32  right
uint32 declaredChannelCount
```

Photoshop commonly writes `24` as the declared count even when the color model needs far fewer channels. The payload then contains `declaredChannelCount + 2` sparse slots. PatKit retains every slot; the penultimate slot is exposed as `userMaskChannel`, and the final slot as `alphaChannel`.

Each slot is:

```text
uint32 written
if written != 0:
  uint32 channelLength
  byte[channelLength] channel
```

A channel has a fixed 23-byte header:

```text
uint32 primaryDepth
int32  top
int32  left
int32  bottom
int32  right
uint16 depth
uint8  compression
byte[] encodedSamples
```

Both depth fields are retained and disagreements become compatibility warnings. Invalid bounds, unsupported depths, and unknown compression markers do not cause the bounded slot to be discarded in tolerant mode.

### Raw samples

Compression `0` stores each byte-padded row directly. The decoded row size is:

```text
ceil(width * depth / 8)
```

One-bit samples are read most-significant bit first. Eight-bit samples are unsigned bytes. Photoshop 16-bit integer samples use its 0–32768 application range. Thirty-two-bit samples are big-endian IEEE 754 single-precision values.

### PackBits samples

Compression `1` begins with one unsigned 16-bit encoded length per row. Each following row is decoded independently with the standard PackBits control-byte rules and must produce exactly the raw row size. Any bytes following the declared rows are exposed as channel trailing data.

## RGBA rendering

`PatPattern.renderRgba8` creates a portable row-major preview while leaving source channels untouched. `canRenderRgba8` reports whether all required color and alpha planes were decoded; rendering throws a `StateError` when they were disabled or use an unsupported encoding.

- Bitmap maps a set bit to black and a clear bit to white.
- Grayscale uses the first plane for red, green, and blue.
- Indexed resolves the first plane through the interleaved palette and applies the transparent index when there is no alpha plane.
- RGB uses the first three planes.
- CMYK interprets Photoshop's inverted colorant samples. A caller converter can provide profile-aware RGB; otherwise an ink-multiplication fallback is used.
- Lab converts the first three planes through D50 XYZ, chromatic adaptation, and sRGB transfer.
- Multichannel and duotone use the first plane as grayscale because PAT records do not contain enough external ink information for an exact composite.
- Unknown modes use the first plane as a stable grayscale preview.

The final sheet-transparency slot supplies alpha when present. User masks are preserved but are not implicitly multiplied into the tile; a host can apply them according to its own compositing semantics.

## Tagged trailers and hierarchy

After the declared records, newer exporters may append tagged blocks:

```text
char[4] signature       // normally "8BIM", optionally "8B64"
char[4] key
uint32  payloadLength   // uint64 when signature is "8B64"
byte[payloadLength] payload
```

Real PAT files may place an odd-length final block at end-of-file without alignment. PatKit accepts that form and only consumes up to three zero padding bytes when another recognizable tagged signature follows.

The `phry` payload starts with descriptor version `16`, followed by a Photoshop Action Descriptor. Its `hierarchy` list contains objects whose observed classes are:

- `Grup`, `group`, or `groupStart` for a group opening;
- `groupEnd` for a closing marker;
- `preset` for a pattern in source order.

Names commonly use `Nm  ` or `name`; identifiers commonly use `zuid` or `Idnt`. PatKit maps known values, tracks nesting depth, resolves presets to decoded patterns, and retains the complete descriptor for fields added by other Photoshop versions.

## Error handling and resource limits

Header errors and truncated unbounded pattern records are fatal because there is no safe record boundary for resynchronization. Inside bounded structures, tolerant mode retains recoverable data and emits a `PatWarning`; strict mode promotes the same condition to `PatFormatException`.

`PatDecodeOptions` bounds the complete input, record count, pattern-name length, dimensions, declared channels, one Virtual Memory Array, aggregate decoded bytes, one tagged payload, hierarchy entries, and descriptor recursion/value counts. The decoder checks names and decoded-size arithmetic before their corresponding allocations.

Preservation is explicit. Applications can retain complete records and encoded slots for forensic round-tripping, or disable those copies while keeping decoded pixels for display.

## Validation corpus

Automated tests include Photoshop-generated RGB, CMYK, Lab, grayscale, multichannel, alpha, raw, and PackBits records redistributed under their source MIT license. Development validation additionally covered large 8-bit and 16-bit libraries, grouped libraries, sparse slots, and tiles up to 3000 × 3000 pixels.

The command below inspects additional local files without making them test dependencies:

```shell
dart run tool/inspect_pat.dart --metadata-only path/to/corpus
```

## References

- Adobe's file-format specification documents shared color-mode values, Action Descriptors, PackBits, and Virtual Memory Array structures.
- psd-tools independently implements the version 1 pattern record and version 3 virtual-memory list.
- Patchy documents and implements standalone PAT compatibility, including hierarchy handling.
- pat-parser provides an independent parser and the redistributable cross-color-mode fixtures used by this package.
