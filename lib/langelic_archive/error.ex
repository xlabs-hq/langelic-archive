defmodule LangelicArchive.Error do
  @moduledoc """
  Error returned from `LangelicArchive` functions.

  The `kind` field is an atom identifying the error class. The `message` field
  is a human-readable string suitable for logging.

  ## Kinds

    * `:unrecognized_format` — the bytes are not a ZIP, RAR, or 7z archive
    * `:encrypted` — the archive (or an entry in it) requires a password
    * `:corrupt` — the archive is recognized but cannot be read
    * `:too_large` — cumulative unpacked size exceeded `:max_total_bytes`
    * `:io` — the archive file could not be opened or read

  Safety:

    * `:panic` — Rust side panicked. This should never happen — report a bug.
  """

  @type kind ::
          :unrecognized_format
          | :encrypted
          | :corrupt
          | :too_large
          | :io
          | :panic

  @type t :: %__MODULE__{kind: kind(), message: String.t()}

  defexception [:kind, :message]

  @impl true
  def message(%__MODULE__{message: m}), do: m
end
