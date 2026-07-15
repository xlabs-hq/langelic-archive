# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Initial release: `extract/2`, `extract_binary/2`, `list/1`, `list_binary/1`,
  and `detect/1` over ZIP, RAR (v4 + v5), and 7z archives.
- Format detection by magic bytes, never by file name.
- Decompression-bomb guard via `:max_total_bytes` (default 4 GiB).
- Precompiled NIFs for macOS (arm64/x86_64) and Linux (arm64/x86_64 gnu,
  x86_64 musl).

[Unreleased]: https://github.com/xlabs-hq/langelic-archive/compare/v0.1.0...HEAD
