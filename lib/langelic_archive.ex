defmodule LangelicArchive do
  @moduledoc """
  Read ZIP, RAR, and 7z archives into memory, backed by a Rustler NIF.

  Extraction only — this library never creates archives (the RAR backend's
  license forbids it, and reading is all it exists for). The format is
  detected from the file's magic bytes, never from its name, so a `.cbz`
  that is secretly a RAR extracts fine.

  All entries are returned in memory as `{name, data}` tuples, in archive
  order. Directory entries are skipped. Nothing is ever written to disk, so
  hostile entry names (`../../etc/passwd`) cannot escape anywhere — but do
  treat names as untrusted input if you persist them.

  ## Example

      {:ok, entries} = LangelicArchive.extract("comic.cbr")
      Enum.map(entries, fn {name, data} -> {name, byte_size(data)} end)

  ## Decompression-bomb guard

  Extraction fails with an `:too_large` error once the cumulative unpacked
  size exceeds `:max_total_bytes` (default #{trunc(4 * :math.pow(1024, 3))}
  bytes — 4 GiB). Raise or lower it per call:

      LangelicArchive.extract(path, max_total_bytes: 100 * 1024 * 1024)
  """

  alias LangelicArchive.Error
  alias LangelicArchive.Native

  @default_max_total_bytes 4 * 1024 * 1024 * 1024

  @type entry :: {name :: String.t(), data :: binary()}
  @type format :: :zip | :rar | :sevenz

  @doc """
  Detect the archive format from the leading magic bytes.

  Accepts the archive's binary content (a prefix is enough). Returns
  `:unknown` for anything that is not a ZIP, RAR (v4 or v5), or 7z archive.
  """
  @spec detect(binary()) :: format() | :unknown
  def detect(<<"PK", 0x03, 0x04, _::binary>>), do: :zip
  def detect(<<"PK", 0x05, 0x06, _::binary>>), do: :zip
  def detect(<<"PK", 0x07, 0x08, _::binary>>), do: :zip
  def detect(<<"Rar!", 0x1A, 0x07, 0x00, _::binary>>), do: :rar
  def detect(<<"Rar!", 0x1A, 0x07, 0x01, 0x00, _::binary>>), do: :rar
  def detect(<<0x37, 0x7A, 0xBC, 0xAF, 0x27, 0x1C, _::binary>>), do: :sevenz
  def detect(data) when is_binary(data), do: :unknown

  @doc """
  Extract every file entry of the archive at `path` into memory.

  Returns entries as `{name, data}` tuples in archive order. Directory
  entries are skipped.

  ## Options

    * `:max_total_bytes` — abort with `:too_large` once cumulative unpacked
      size exceeds this (default 4 GiB).
  """
  @spec extract(Path.t(), keyword()) :: {:ok, [entry()]} | {:error, Error.t()}
  def extract(path, opts \\ []) do
    max_total_bytes = Keyword.get(opts, :max_total_bytes, @default_max_total_bytes)

    path
    |> to_string()
    |> Native.extract_all(max_total_bytes)
    |> wrap()
  end

  @doc """
  Extract archive content already held in memory.

  The RAR backend can only read from the filesystem, so the data is staged
  through a temporary file (removed before returning). Prefer `extract/2`
  when the archive is already on disk.
  """
  @spec extract_binary(binary(), keyword()) :: {:ok, [entry()]} | {:error, Error.t()}
  def extract_binary(data, opts \\ []) when is_binary(data) do
    with_temp_file(data, &extract(&1, opts))
  end

  @doc """
  List the file entries of the archive at `path` without decompressing them.

  Returns `{name, unpacked_size}` tuples in archive order.
  """
  @spec list(Path.t()) :: {:ok, [{String.t(), non_neg_integer()}]} | {:error, Error.t()}
  def list(path) do
    path |> to_string() |> Native.list() |> wrap()
  end

  @doc """
  List the file entries of archive content already held in memory.
  """
  @spec list_binary(binary()) ::
          {:ok, [{String.t(), non_neg_integer()}]} | {:error, Error.t()}
  def list_binary(data) when is_binary(data) do
    with_temp_file(data, &list/1)
  end

  defp with_temp_file(data, fun) do
    path =
      Path.join(
        System.tmp_dir!(),
        "langelic-archive-#{System.unique_integer([:positive])}"
      )

    case File.write(path, data) do
      :ok ->
        result = fun.(path)
        File.rm(path)
        result

      {:error, posix} ->
        {:error, %Error{kind: :io, message: "could not stage temp file: #{posix}"}}
    end
  end

  defp wrap({:ok, entries}), do: {:ok, entries}
  defp wrap({:error, {kind, message}}), do: {:error, %Error{kind: kind, message: message}}
end
