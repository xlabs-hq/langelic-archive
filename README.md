# LangelicArchive

Read ZIP, RAR, and 7z archives into memory from Elixir, backed by a
[Rustler](https://github.com/rusterlium/rustler) NIF.

- **Extraction only.** This library never creates archives — the RAR
  backend's license forbids building an archiver, and reading is all it
  exists for.
- **Magic bytes, not file names.** The format is sniffed from the leading
  bytes, so a `.cbz` that is secretly a RAR extracts fine.
- **In-memory.** Entries come back as `{name, binary}` tuples in archive
  order; nothing is written to disk. Directory entries are skipped.
- **Bounded.** Extraction aborts with a `:too_large` error once the
  cumulative unpacked size exceeds `:max_total_bytes` (default 4 GiB), so a
  decompression bomb can't take the VM down.

Backends: the [`zip`](https://crates.io/crates/zip) crate,
[`unrar`](https://crates.io/crates/unrar) (rarlab's vendored unrar C++
source — see [NOTICE](NOTICE)), and
[`sevenz-rust2`](https://crates.io/crates/sevenz-rust2) (pure Rust).

## Usage

```elixir
{:ok, entries} = LangelicArchive.extract("comic.cbr")
# => [{"page_001.png", <<137, 80, ...>>}, ...]

{:ok, entries} = LangelicArchive.extract_binary(downloaded_bytes)

{:ok, listing} = LangelicArchive.list("book.7z")
# => [{"page_001.png", 482_113}, ...]

LangelicArchive.detect(<<"Rar!", 0x1A, 0x07, 0x01, 0x00, rest::binary>>)
# => :rar

LangelicArchive.extract("huge.zip", max_total_bytes: 100 * 1024 * 1024)
# => {:error, %LangelicArchive.Error{kind: :too_large}}
```

Password-protected archives fail with `kind: :encrypted`; bytes that are not
a ZIP/RAR/7z fail with `kind: :unrecognized_format`. See
`LangelicArchive.Error` for the full list.

## Installation

```elixir
def deps do
  [
    {:langelic_archive, "~> 0.1"}
  ]
end
```

Precompiled NIF binaries ship for macOS (arm64/x86_64) and Linux
(arm64/x86_64 gnu, x86_64 musl) — no Rust toolchain needed. To force a
source build (requires Rust and a C++ compiler for the unrar backend):

```shell
LANGELIC_ARCHIVE_BUILD=true mix deps.compile langelic_archive
```

## Development

```shell
just test    # full suite, NIF built from source
just check   # every CI gate, locally
just release # interactive: bump, tag, push — CI builds and publishes
```

The first release has no prior tag: bump nothing, just `git tag v0.1.0 &&
git push origin v0.1.0` and approve the `hex` environment when the workflow
pauses. See [UPDATE_PROCEDURE.md](UPDATE_PROCEDURE.md) for the release
mechanics and dependency-bump routine.

## License

MIT, except the vendored unrar C++ source, which ships under rarlab's
freeware [unrar license](NOTICE) (extraction only).
