defmodule LangelicArchive.Native do
  @moduledoc false

  version = Mix.Project.config()[:version]

  use RustlerPrecompiled,
    otp_app: :langelic_archive,
    crate: "langelic_archive",
    base_url: "https://github.com/xlabs-hq/langelic-archive/releases/download/v#{version}",
    # End users on :prod get the precompiled binary matching their platform.
    # Local dev and tests always compile from source so CI and contributors
    # never race against Release workflow timing. The compile_env clause must
    # stay: when this library is compiled as a dependency, Mix.env() is
    # always :prod and rustler_precompiled's own config lookup is shadowed by
    # an explicit force_build (Keyword.put_new) — so honor the standard
    # `config :rustler_precompiled, :force_build, langelic_archive: true`
    # here ourselves.
    force_build:
      System.get_env("LANGELIC_ARCHIVE_BUILD") in ["1", "true"] or
        Mix.env() in [:dev, :test] or
        Application.compile_env(:rustler_precompiled, [:force_build, :langelic_archive], false),
    targets: ~w(
      aarch64-apple-darwin
      x86_64-apple-darwin
      aarch64-unknown-linux-gnu
      x86_64-unknown-linux-gnu
      x86_64-unknown-linux-musl
    ),
    nif_versions: ["2.16"],
    version: version

  def list(_path), do: :erlang.nif_error(:nif_not_loaded)
  def extract_all(_path, _max_total_bytes), do: :erlang.nif_error(:nif_not_loaded)
end
