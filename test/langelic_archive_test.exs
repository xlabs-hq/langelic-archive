defmodule LangelicArchiveTest do
  use ExUnit.Case, async: true

  alias LangelicArchive.Error

  doctest LangelicArchive

  @fixtures Path.expand("fixtures", __DIR__)

  @sample_names ["notes.txt", "pages/page_001.png", "pages/page_002.png"]

  defp fixture(name), do: Path.join(@fixtures, name)

  describe "extract/2" do
    for name <- ["sample.zip", "sample.rar", "sample.7z"] do
      test "extracts #{name} into memory" do
        assert {:ok, entries} = LangelicArchive.extract(fixture(unquote(name)))

        assert entries |> Enum.map(&elem(&1, 0)) |> Enum.sort() == @sample_names

        assert {_, "sample notes\n"} =
                 Enum.find(entries, fn {name, _} -> name == "notes.txt" end)

        for page <- ["pages/page_001.png", "pages/page_002.png"] do
          {_, data} = Enum.find(entries, fn {name, _} -> name == page end)
          assert <<0x89, "PNG", _::binary>> = data
        end
      end
    end

    test "extracts legacy RAR v4 archives" do
      assert {:ok, [{"VERSION", data}]} = LangelicArchive.extract(fixture("legacy-rar4.rar"))
      assert byte_size(data) == 11
    end

    test "returns :encrypted for password-protected RAR" do
      assert {:error, %Error{kind: :encrypted}} =
               LangelicArchive.extract(fixture("encrypted.rar"))
    end

    test "returns :encrypted for password-protected 7z" do
      assert {:error, %Error{kind: :encrypted}} =
               LangelicArchive.extract(fixture("encrypted.7z"))
    end

    for name <- ["sample.zip", "sample.rar", "sample.7z"] do
      test "enforces max_total_bytes on #{name}" do
        assert {:error, %Error{kind: :too_large}} =
                 LangelicArchive.extract(fixture(unquote(name)), max_total_bytes: 10)
      end
    end

    test "returns :unrecognized_format for non-archive bytes" do
      path = Path.join(System.tmp_dir!(), "langelic-archive-test-#{System.unique_integer()}")
      File.write!(path, "just some text, definitely not an archive")
      on_exit(fn -> File.rm(path) end)

      assert {:error, %Error{kind: :unrecognized_format}} = LangelicArchive.extract(path)
    end

    test "returns :corrupt for a truncated archive" do
      # ZIP: the central directory lives at the end, so any truncation kills it.
      zip = File.read!(fixture("sample.zip"))

      assert {:error, %Error{kind: :corrupt}} =
               LangelicArchive.extract_binary(binary_part(zip, 0, 60))

      # RAR: truncate mid-entry-data → CRC error. (RAR streams its headers,
      # so a cut that lands exactly between entries is indistinguishable from
      # end-of-archive and yields a silent partial result instead.)
      rar = File.read!(fixture("sample.rar"))

      assert {:error, %Error{kind: :corrupt}} =
               LangelicArchive.extract_binary(binary_part(rar, 0, 300))
    end

    test "returns :io for a missing file" do
      assert {:error, %Error{kind: :io}} = LangelicArchive.extract("/nonexistent/nope.zip")
    end
  end

  describe "extract_binary/2" do
    test "extracts in-memory RAR data (format sniffed, no name available)" do
      data = File.read!(fixture("sample.rar"))

      assert {:ok, entries} = LangelicArchive.extract_binary(data)
      assert entries |> Enum.map(&elem(&1, 0)) |> Enum.sort() == @sample_names
    end
  end

  describe "list/1 and list_binary/1" do
    for name <- ["sample.zip", "sample.rar", "sample.7z"] do
      test "lists #{name} without extracting" do
        assert {:ok, listing} = LangelicArchive.list(fixture(unquote(name)))
        assert listing |> Enum.map(&elem(&1, 0)) |> Enum.sort() == @sample_names

        assert {_, 13} = Enum.find(listing, fn {name, _} -> name == "notes.txt" end)
      end
    end

    test "lists from memory" do
      data = File.read!(fixture("sample.7z"))
      assert {:ok, listing} = LangelicArchive.list_binary(data)
      assert length(listing) == 3
    end
  end

  describe "detect/1" do
    test "detects formats from magic bytes regardless of name" do
      assert LangelicArchive.detect(File.read!(fixture("sample.zip"))) == :zip
      assert LangelicArchive.detect(File.read!(fixture("sample.rar"))) == :rar
      assert LangelicArchive.detect(File.read!(fixture("legacy-rar4.rar"))) == :rar
      assert LangelicArchive.detect(File.read!(fixture("sample.7z"))) == :sevenz
      assert LangelicArchive.detect("plain text") == :unknown
      assert LangelicArchive.detect(<<>>) == :unknown
    end
  end
end
