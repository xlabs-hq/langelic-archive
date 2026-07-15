defmodule LangelicArchive.MixProject do
  use Mix.Project

  # Do not hand-edit. The release script (`scripts/release.exs`, via `just
  # release`) bumps this line, native/langelic_archive/Cargo.toml, and the
  # CHANGELOG together; editing it by hand desyncs them (bin/check_versions
  # gates this) and the precompiled-NIF release dance (see UPDATE_PROCEDURE.md).
  @version "0.1.0"
  @source_url "https://github.com/xlabs-hq/langelic-archive"

  def project do
    [
      app: :langelic_archive,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      docs: docs(),
      description:
        "Read ZIP, RAR, and 7z archives into memory from Elixir, backed by a Rustler NIF.",
      source_url: @source_url,
      dialyzer: [
        plt_core_path: "priv/plts",
        plt_file: {:no_warn, "priv/plts/project.plt"},
        flags: [:error_handling, :unknown, :underspecs]
      ]
    ]
  end

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:rustler_precompiled, "~> 0.8"},
      {:rustler, "~> 0.38", optional: true},
      {:ex_doc, "~> 0.34", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false}
    ]
  end

  defp package do
    [
      files: ~w(
        lib
        native/langelic_archive/src
        native/langelic_archive/Cargo.toml
        native/langelic_archive/Cargo.lock
        native/langelic_archive/.cargo
        checksum-Elixir.LangelicArchive.Native.exs
        mix.exs
        README.md
        LICENSE
        NOTICE
        CHANGELOG.md
      ),
      licenses: ["MIT"],
      links: %{"GitHub" => @source_url}
    ]
  end

  defp docs do
    [
      main: "LangelicArchive",
      source_ref: "v#{@version}",
      extras: ["README.md", "CHANGELOG.md"]
    ]
  end
end
