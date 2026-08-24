import 'package:pscore/pscore.dart';

/// Photoshop color model stored by a PAT pattern.
typedef PatColorMode = PsPatternColorMode;

/// Compression method stored by a PAT pattern channel.
typedef PatCompression = PsPatternCompression;

/// Source-space rectangle stored by PAT virtual-memory data.
typedef PatRectangle = PsRectangle;

/// Indexed palette metadata stored by a standalone PAT record.
typedef PatIndexedMetadata = PsPatternIndexedMetadata;

/// One decoded or preserved PAT channel.
typedef PatPatternChannel = PsPatternChannel;

/// One declared virtual-memory slot belonging to a PAT pattern.
typedef PatPatternChannelSlot = PsPatternChannelSlot;

/// A rendered RGBA tile suitable for Focale integration.
typedef PatPatternImage = PsPatternImage;

/// One complete pattern preset from a PAT library.
typedef PatPattern = PsPattern;
