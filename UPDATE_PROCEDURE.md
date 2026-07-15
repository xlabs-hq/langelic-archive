# LangelicArchive Update & Release Procedure

Two things drift over time and need a deliberate procedure:

1. **The Rust crates** that back the NIF — pinned in
   `native/langelic_archive/Cargo.toml` (`zip`, `unrar`, `sevenz-rust2`,
   `rustler`, …). Dependabot opens weekly PRs for these; review them with the
   notes below.
2. **The supported Elixir/OTP and NIF ABI** — the CI matrix, the
   `nif_versions`/`targets` in `lib/langelic_archive/native.ex`, and the
   release matrix in `.github/workflows/release.yml`.

And one thing must happen in a **specific order** every release: regenerating
the precompiled-NIF checksum file. That's the part everyone gets wrong; it's
last, and CI does it for you.

---

## Part A — Bumping the Rust crates

All deps are on crates.io, so track **released versions**, not git refs.

1. See what Dependabot proposes (or check manually):
   ```bash
   cargo update --manifest-path native/langelic_archive/Cargo.toml --dry-run
   ```
2. Read the crate's CHANGELOG for breaking changes to the APIs we touch:
   - `zip` — `ZipArchive`, `by_index`/`by_index_raw`, `encrypted()`.
   - `unrar` — the cursored `open_for_processing`/`read_header`/`read` API
     and `unrar::error::Code`. An `unrar_sys` bump also bumps the **vendored
     rarlab C++ source**; skim rarlab's release notes for new RAR format
     revisions.
   - `sevenz-rust2` — `ArchiveReader`, `for_each_entries`, `Password`,
     `Error::PasswordRequired`.
   - `rustler` — NIF ABI. A rustler bump can change the **NIF version**; if
     it does, update `nif_versions` in `native.ex`, the `nif` matrix in
     `release.yml`, and the `default = ["nif_version_2_XX"]` feature in
     `Cargo.toml` together. The release artifact built against the lowest NIF
     version loads on all newer OTPs — this is why we ship one artifact per
     target, not per OTP.
3. Bump, then prove it locally with a real build (not the precompiled
   download):
   ```bash
   cargo update -p <crate> --manifest-path native/langelic_archive/Cargo.toml
   LANGELIC_ARCHIVE_BUILD=true mix test
   ```
4. Fix any signature/type drift. **Map** changes across the NIF boundary —
   keep format semantics in the Rust crates, not re-implemented in Elixir.

> **Security:** if `zip`/`unrar`/`sevenz-rust2` fix a parsing or
> decompression-bomb advisory, bump promptly and cut a patch release. This
> library exists to feed untrusted user uploads into the VM.

---

## Part B — Bumping the toolchain / supported versions

- **CI matrix** (`.github/workflows/ci.yml`) — the OTP/Elixir combos we
  test. Add a newer OTP/Elixir row when one ships; keep the oldest supported
  row matching `elixir: "~> 1.15"` in `mix.exs`.
- **Release targets** (`.github/workflows/release.yml` + `targets` in
  `native.ex`) — keep the two lists identical. Every target must have a C++
  cross-toolchain available (the unrar backend compiles C++); cross's docker
  images and the macOS runners all ship one.

---

## Part C — Releasing

```bash
just release
```

The script bumps `mix.exs` + `Cargo.toml` in lockstep, rolls the CHANGELOG,
tags, and pushes. The Release workflow builds the per-target NIF artifacts,
attaches them to the GitHub release, **regenerates the checksum file from
those artifacts**, and pauses on the `hex` environment for your approval
before publishing to Hex.

First release only: there is no previous tag, so skip the bump —
`git tag -a v0.1.0 -m v0.1.0 && git push origin v0.1.0`.
