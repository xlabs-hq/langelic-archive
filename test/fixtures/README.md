# Test fixtures

`sample.{zip,rar,7z}` and `encrypted.{rar,7z}` all contain the same tree:

```
pages/page_001.png   (tiny blank PNG)
pages/page_002.png   (identical copy)
notes.txt            ("sample notes\n")
```

Authored on macOS (2026-07) with:

- `zip -r sample.zip pages notes.txt` (Info-ZIP 3.0)
- `7zz a sample.7z pages notes.txt` and `7zz a -psecret encrypted.7z …` (7-Zip 24.x)
- `rar a -ma5 sample.rar pages notes.txt` and `rar a -ma5 -psecret encrypted.rar …`
  (RAR 7.23 trial, rarlab.com)

`legacy-rar4.rar` is the RAR-v4-family archive `data/version.rar` from the
`unrar` crate's test data (one 11-byte file named `VERSION`). RAR 7.x can no
longer author v4 archives, so we keep this one as the old-format read
regression — most scanned `.cbr` files in the wild are still RAR4.
