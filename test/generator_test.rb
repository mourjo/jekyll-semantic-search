# frozen_string_literal: true

require "test_helper"
require "support/hashing_embedder"

class GeneratorTest < Minitest::Test
  FIXTURE = File.expand_path("fixtures/site", __dir__)

  def setup
    @tmp = Dir.mktmpdir
    @embedder = HashingEmbedder.new
    Jekyll::SemanticSearch.embedder_factory = ->(_config) { @embedder }
  end

  def teardown
    Jekyll::SemanticSearch.embedder_factory = nil
    FileUtils.rm_rf(@tmp)
  end

  def build(overrides = {})
    config = Jekyll.configuration(
      "source" => FIXTURE,
      "destination" => File.join(@tmp, "_site"),
      "cache_dir" => File.join(@tmp, "cache"),
      "quiet" => true
    ).merge(overrides)
    Jekyll::Site.new(config).tap(&:process)
  end

  def database
    SQLite3::Database.new(File.join(@tmp, "_site/assets/semantic-search/index.sqlite3"))
  end

  def test_writes_database_and_runtime
    build

    %w[index.sqlite3 semantic-search.js search-core.js].each do |file|
      assert_path_exists File.join(@tmp, "_site/assets/semantic-search", file)
    end
  end

  def test_indexes_posts_except_opted_out_ones
    build
    rows = database.execute("SELECT url, title, data FROM documents ORDER BY date")

    assert_equal [
      ["/blog/2026/01/10/sourdough.html", "Baking sourdough bread", '{"tags":["baking"]}'],
      ["/blog/2026/02/14/rust.html", "Ownership in Rust", "{}"]
    ], rows
  end

  def test_chunks_rendered_content_without_layout
    build
    chunks = database.execute(<<~SQL).flatten
      SELECT content FROM chunks JOIN documents d ON d.id = document_id
      WHERE d.title = 'Baking sourdough bread' ORDER BY position
    SQL

    assert_operator chunks.size, :>, 1
    assert chunks.first.start_with?("Sourdough bread needs a lively starter")
    refute(chunks.any? { |c| c.include?("Site navigation") })
  end

  def test_embeds_title_document_prefix_and_passage
    build("semantic_search" => { "chunk_size" => 12, "chunk_overlap" => 2, "document_prefix" => "passage: " })
    inputs = @embedder.calls.flatten

    assert_includes inputs, "passage: Ownership in Rust\nThe borrow checker enforces ownership rules at compile time, " \
                            "which prevents data"
  end

  def test_records_query_settings_in_meta
    build
    meta = database.execute("SELECT key, value FROM meta").to_h

    assert_equal '"query: "', meta["query_prefix"]
    assert_equal HashingEmbedder::DIMENSIONS.to_s, meta["dimensions"]
  end

  def test_rebuild_reuses_cached_embeddings
    build
    @embedder = HashingEmbedder.new
    build

    assert_empty @embedder.calls
  end

  def test_tag_renders_runtime_config
    build
    html = File.read(File.join(@tmp, "_site/index.html"))
    config = JSON.parse(html[%r{<script type="application/json" id="semantic-search-config">(.*?)</script>}, 1])

    assert_equal "/blog/assets/semantic-search/index.sqlite3", config["databaseUrl"]
    assert_match %r{@huggingface/transformers@}, config["transformersUrl"]
    assert_includes html, '<script type="module" src="/blog/assets/semantic-search/semantic-search.js"></script>'
  end

  def test_disabled_plugin_writes_nothing
    build("semantic_search" => { "enabled" => false })

    refute_path_exists File.join(@tmp, "_site/assets/semantic-search")
    refute_includes File.read(File.join(@tmp, "_site/index.html")), "semantic-search"
  end
end
