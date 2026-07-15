//! Rustler NIF for reading ZIP, RAR, and 7z archives into memory.
//!
//! The format is sniffed from magic bytes, never from the file name. All
//! entry data is returned as Erlang binaries; nothing is written to disk.
//! Both NIFs run on dirty IO schedulers — extraction of a large archive can
//! take seconds.

use std::fs::File;
use std::io::{BufReader, Read};

use rustler::{Encoder, Env, OwnedBinary, Term};

mod atoms {
    rustler::atoms! {
        unrecognized_format,
        encrypted,
        corrupt,
        too_large,
        io,
    }
}

// ---------------------------------------------------------------------------
// Error mapping
// ---------------------------------------------------------------------------

/// Encoded to Elixir as `{kind_atom, message}`; the Elixir side wraps it into
/// a `%LangelicArchive.Error{}`.
enum ArchiveError {
    UnrecognizedFormat,
    Encrypted,
    Corrupt(String),
    TooLarge(u64),
    Io(String),
}

impl Encoder for ArchiveError {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        match self {
            ArchiveError::UnrecognizedFormat => (
                atoms::unrecognized_format(),
                "not a ZIP, RAR, or 7z archive",
            )
                .encode(env),
            ArchiveError::Encrypted => {
                (atoms::encrypted(), "archive requires a password").encode(env)
            }
            ArchiveError::Corrupt(msg) => (atoms::corrupt(), msg).encode(env),
            ArchiveError::TooLarge(cap) => (
                atoms::too_large(),
                format!("unpacked size exceeds max_total_bytes ({cap})"),
            )
                .encode(env),
            ArchiveError::Io(msg) => (atoms::io(), msg).encode(env),
        }
    }
}

fn io_err(e: std::io::Error) -> ArchiveError {
    ArchiveError::Io(e.to_string())
}

/// Owned bytes that encode as an Erlang binary (a bare `Vec<u8>` would
/// encode as a list of integers).
struct Bytes(Vec<u8>);

impl Encoder for Bytes {
    fn encode<'a>(&self, env: Env<'a>) -> Term<'a> {
        let mut bin = OwnedBinary::new(self.0.len()).expect("binary allocation failed");
        bin.as_mut_slice().copy_from_slice(&self.0);
        Term::from(bin.release(env))
    }
}

// ---------------------------------------------------------------------------
// Format sniffing
// ---------------------------------------------------------------------------

#[derive(Clone, Copy)]
enum Format {
    Zip,
    Rar,
    SevenZ,
}

fn sniff(path: &str) -> Result<Format, ArchiveError> {
    let mut file = File::open(path).map_err(io_err)?;
    let mut buf = [0u8; 8];
    let n = file.read(&mut buf).map_err(io_err)?;
    let head = &buf[..n];

    if head.starts_with(b"PK\x03\x04")
        || head.starts_with(b"PK\x05\x06")
        || head.starts_with(b"PK\x07\x08")
    {
        Ok(Format::Zip)
    } else if head.starts_with(b"Rar!\x1A\x07\x00") || head.starts_with(b"Rar!\x1A\x07\x01\x00") {
        Ok(Format::Rar)
    } else if head.starts_with(b"7z\xBC\xAF\x27\x1C") {
        Ok(Format::SevenZ)
    } else {
        Err(ArchiveError::UnrecognizedFormat)
    }
}

// ---------------------------------------------------------------------------
// NIFs
// ---------------------------------------------------------------------------

#[rustler::nif(schedule = "DirtyIo")]
fn extract_all(path: String, max_total_bytes: u64) -> Result<Vec<(String, Bytes)>, ArchiveError> {
    match sniff(&path)? {
        Format::Zip => extract_zip(&path, max_total_bytes),
        Format::Rar => extract_rar(&path, max_total_bytes),
        Format::SevenZ => extract_sevenz(&path, max_total_bytes),
    }
}

#[rustler::nif(schedule = "DirtyIo")]
fn list(path: String) -> Result<Vec<(String, u64)>, ArchiveError> {
    match sniff(&path)? {
        Format::Zip => list_zip(&path),
        Format::Rar => list_rar(&path),
        Format::SevenZ => list_sevenz(&path),
    }
}

rustler::init!("Elixir.LangelicArchive.Native");

// ---------------------------------------------------------------------------
// ZIP backend
// ---------------------------------------------------------------------------

fn zip_err(e: zip::result::ZipError) -> ArchiveError {
    match &e {
        zip::result::ZipError::UnsupportedArchive(msg) if msg.contains("Password") => {
            ArchiveError::Encrypted
        }
        _ => ArchiveError::Corrupt(e.to_string()),
    }
}

fn open_zip(path: &str) -> Result<zip::ZipArchive<BufReader<File>>, ArchiveError> {
    let file = File::open(path).map_err(io_err)?;
    zip::ZipArchive::new(BufReader::new(file)).map_err(zip_err)
}

fn extract_zip(path: &str, cap: u64) -> Result<Vec<(String, Bytes)>, ArchiveError> {
    let mut archive = open_zip(path)?;
    let mut out = Vec::new();
    let mut total: u64 = 0;

    for i in 0..archive.len() {
        let mut entry = archive.by_index(i).map_err(zip_err)?;
        if !entry.is_file() {
            continue;
        }
        if entry.encrypted() {
            return Err(ArchiveError::Encrypted);
        }

        let name = entry.name().to_string();
        // Trust the declared size only as a pre-check; the guarded reader
        // below enforces the cap against what actually inflates.
        if total.saturating_add(entry.size()) > cap {
            return Err(ArchiveError::TooLarge(cap));
        }

        let data = read_capped(&mut entry, cap - total)?.ok_or(ArchiveError::TooLarge(cap))?;
        total += data.len() as u64;
        out.push((name, Bytes(data)));
    }

    Ok(out)
}

fn list_zip(path: &str) -> Result<Vec<(String, u64)>, ArchiveError> {
    let mut archive = open_zip(path)?;
    let mut out = Vec::new();

    for i in 0..archive.len() {
        let entry = archive.by_index_raw(i).map_err(zip_err)?;
        if entry.is_file() {
            out.push((entry.name().to_string(), entry.size()));
        }
    }

    Ok(out)
}

/// Read at most `budget` bytes; `None` means the entry inflated past it.
fn read_capped<R: Read + ?Sized>(
    reader: &mut R,
    budget: u64,
) -> Result<Option<Vec<u8>>, ArchiveError> {
    let mut data = Vec::new();
    reader
        .take(budget.saturating_add(1))
        .read_to_end(&mut data)
        .map_err(io_err)?;
    if data.len() as u64 > budget {
        Ok(None)
    } else {
        Ok(Some(data))
    }
}

// ---------------------------------------------------------------------------
// RAR backend (rarlab unrar via the `unrar` crate)
// ---------------------------------------------------------------------------

fn rar_err(e: unrar::error::UnrarError) -> ArchiveError {
    match e.code {
        unrar::error::Code::MissingPassword => ArchiveError::Encrypted,
        _ => ArchiveError::Corrupt(e.to_string()),
    }
}

fn extract_rar(path: &str, cap: u64) -> Result<Vec<(String, Bytes)>, ArchiveError> {
    let mut archive = unrar::Archive::new(path)
        .open_for_processing()
        .map_err(rar_err)?;
    let mut out = Vec::new();
    let mut total: u64 = 0;

    while let Some(header) = archive.read_header().map_err(rar_err)? {
        let entry = header.entry();
        let name = entry.filename.to_string_lossy().into_owned();
        let is_file = entry.is_file();
        let size = entry.unpacked_size;

        archive = if is_file {
            total = total.saturating_add(size);
            if total > cap {
                return Err(ArchiveError::TooLarge(cap));
            }
            let (data, next) = header.read().map_err(rar_err)?;
            out.push((name, Bytes(data)));
            next
        } else {
            header.skip().map_err(rar_err)?
        };
    }

    Ok(out)
}

fn list_rar(path: &str) -> Result<Vec<(String, u64)>, ArchiveError> {
    let archive = unrar::Archive::new(path)
        .open_for_listing()
        .map_err(rar_err)?;
    let mut out = Vec::new();

    for entry in archive {
        let entry = entry.map_err(rar_err)?;
        if entry.is_file() {
            out.push((
                entry.filename.to_string_lossy().into_owned(),
                entry.unpacked_size,
            ));
        }
    }

    Ok(out)
}

// ---------------------------------------------------------------------------
// 7z backend (sevenz-rust2)
// ---------------------------------------------------------------------------

fn sevenz_err(e: sevenz_rust2::Error) -> ArchiveError {
    match &e {
        sevenz_rust2::Error::PasswordRequired => ArchiveError::Encrypted,
        _ => ArchiveError::Corrupt(e.to_string()),
    }
}

fn open_sevenz(path: &str) -> Result<sevenz_rust2::ArchiveReader<File>, ArchiveError> {
    let file = File::open(path).map_err(io_err)?;
    sevenz_rust2::ArchiveReader::new(file, sevenz_rust2::Password::empty()).map_err(sevenz_err)
}

fn extract_sevenz(path: &str, cap: u64) -> Result<Vec<(String, Bytes)>, ArchiveError> {
    let mut reader = open_sevenz(path)?;
    let mut out = Vec::new();
    let mut total: u64 = 0;
    // The closure's error type can't carry ArchiveError, so smuggle failures
    // out through this slot and stop iteration with Ok(false).
    let mut failure: Option<ArchiveError> = None;

    reader
        .for_each_entries(|entry, entry_reader| {
            if entry.is_directory() {
                return Ok(true);
            }
            match read_capped(entry_reader, cap - total) {
                Ok(Some(data)) => {
                    total += data.len() as u64;
                    out.push((entry.name().to_string(), Bytes(data)));
                    Ok(true)
                }
                Ok(None) => {
                    failure = Some(ArchiveError::TooLarge(cap));
                    Ok(false)
                }
                Err(e) => {
                    failure = Some(e);
                    Ok(false)
                }
            }
        })
        .map_err(sevenz_err)?;

    if let Some(e) = failure {
        return Err(e);
    }

    Ok(out)
}

fn list_sevenz(path: &str) -> Result<Vec<(String, u64)>, ArchiveError> {
    let reader = open_sevenz(path)?;
    let out = reader
        .archive()
        .files
        .iter()
        .filter(|entry| !entry.is_directory())
        .map(|entry| (entry.name().to_string(), entry.size()))
        .collect();

    Ok(out)
}
