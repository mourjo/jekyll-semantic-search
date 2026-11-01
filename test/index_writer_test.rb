# frozen_string_literal: true

require "test_helper"

class IndexWriterTest < Minitest::Test
  IndexWriter = Jekyll::SemanticSearch::IndexWriter
  Configuration = Jekyll::SemanticSearch::Configuration

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "out", "index.sqlite3")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def entries
    [
      {
        url: "/a/", title: "A", date: "2026-01-01", excerpt: "about a", data: { "tags" => ["x"] },
        chunks: [{ content: "first", vector: [1.0, 0.0] }, { content: "second", vector: [0.0, 1.0] }]
      },
      { url: "/b/", title: "B", date: nil, excerpt: nil, data: nil, chunks: [{ content: "third", vector: [0.5, 0.5] }] }
    ]
  end

  def write(settings = {}, calibration = nil)
    IndexWriter.new(Configuration.new("semantic_search" => settings)).write(@path, entries, calibration: calibration)
    SQLite3::Database.new(@path)
  end

  def meta(db)
    db.execute("SELECT key, value FROM meta").to_h { |k, v| [k, JSON.parse(v)] }
  end

  def test_writes_meta_for_the_browser
    db = write("query_prefix" => "query: ")
    meta = db.execute("SELECT key, value FROM meta").to_h { |k, v| [k, JSON.parse(v)] }

    assert_equal "Xenova/all-MiniLM-L6-v2", meta["model"]
    assert_equal "q8", meta["dtype"]
    assert_equal "mean", meta["pooling"]
    assert meta["normalize"]
    assert_equal "query: ", meta["query_prefix"]
    assert_equal 2, meta["dimensions"]
    assert_equal IndexWriter::SCHEMA_VERSION, meta["schema_version"]
  end

  def test_min_score_is_null_by_default
    meta = meta(write)

    assert meta.key?("min_score")
    assert_nil meta["min_score"]
    refute meta.key?("min_score_calibration")
  end

  def test_writes_keyword_weight
    assert_equal 0, meta(write)["keyword_weight"]
    assert_in_delta 0.15, meta(write("keyword_weight" => 0.15))["keyword_weight"]
  end

  def test_writes_numeric_min_score
    assert_in_delta 0.35, meta(write("min_score" => 0.35))["min_score"]
  end

  def test_writes_calibrated_min_score
    calibration = Jekyll::SemanticSearch::MinScoreCalibrator::Result.new(min_score: 0.29, noise: 0.2, relevance: 0.8)
    meta = meta(write({ "min_score" => "auto" }, calibration))

    assert_in_delta 0.29, meta["min_score"]
    assert_equal({ "min_score" => 0.29, "noise" => 0.2, "relevance" => 0.8 }, meta["min_score_calibration"])
  end

  def test_auto_without_calibration_writes_null
    assert_nil meta(write("min_score" => "auto"))["min_score"]
  end

  def test_writes_documents_and_chunks
    db = write

    assert_equal [[1, "/a/", "A", '{"tags":["x"]}'], [2, "/b/", "B", nil]],
                 db.execute("SELECT id, url, title, data FROM documents ORDER BY id")
    rows = db.execute("SELECT document_id, position, content, embedding FROM chunks ORDER BY id")

    assert_equal [[1, 0, "first"], [1, 1, "second"], [2, 0, "third"]], rows.map { |r| r[0, 3] }
    assert_equal [0.0, 1.0], Jekyll::SemanticSearch::Vector.unpack(rows[1][3])
    assert_equal 8, rows[1][3].bytesize
  end

  def test_can_omit_chunk_content
    db = write("store_content" => false)

    assert_equal [[nil]], db.execute("SELECT DISTINCT content FROM chunks")
  end

  def test_overwrites_existing_database
    write.close
    db = write

    assert_equal 2, db.get_first_value("SELECT COUNT(*) FROM documents")
    refute_path_exists "#{@path}.tmp"
  end

  def test_rejects_mixed_dimensions
    bad = [{ url: "/", chunks: [{ content: "a", vector: [1.0] }, { content: "b", vector: [1.0, 2.0] }] }]

    assert_raises(Jekyll::SemanticSearch::Error) { IndexWriter.new(Configuration.new({})).write(@path, bad) }
  end
end
