# frozen_string_literal: true

require "test_helper"
require "support/hashing_embedder"

class MinScoreCalibratorTest < Minitest::Test
  Calibrator = Jekyll::SemanticSearch::MinScoreCalibrator
  Configuration = Jekyll::SemanticSearch::Configuration

  def entry(title, *passages)
    { title: title, chunks: passages.map { |p| { content: p, vector: HashingEmbedder.vector("#{title}\n#{p}") } } }
  end

  def entries
    [
      entry("Baking sourdough bread", "Feed the starter with flour and water", "Bake the loaf in a hot oven"),
      entry("Ownership in Rust", "The borrow checker enforces ownership at compile time"),
      entry("Growing tomatoes", "Tomatoes need sun water and support stakes")
    ]
  end

  def calibrate(entries, settings = {})
    @embedder = HashingEmbedder.new
    Calibrator.new(Configuration.new("semantic_search" => settings), @embedder).calibrate(entries)
  end

  def test_threshold_sits_between_unrelated_queries_and_titles
    result = calibrate(entries)

    assert_operator result.relevance, :>, result.noise
    assert_in_delta result.noise + (Calibrator::MARGIN * (result.relevance - result.noise)), result.min_score, 1e-3
  end

  def test_threshold_admits_title_queries_and_rejects_most_probes
    result = calibrate(entries)
    chunks = entries.flat_map { |e| e[:chunks].map { |c| c[:vector] } }
    best = ->(query) { chunks.map { |c| Jekyll::SemanticSearch::Vector.cosine(HashingEmbedder.vector(query), c) }.max }

    entries.each { |e| assert_operator best.(e[:title]), :>=, result.min_score, e[:title] }
    rejected = Calibrator::PROBES.count { |probe| best.(probe) < result.min_score }

    assert_operator rejected, :>=, (Calibrator::PROBES.size * Calibrator::NOISE_PERCENTILE).floor
  end

  def test_embeds_probes_and_titles_as_queries
    calibrate(entries, "query_prefix" => "query: ")
    inputs = @embedder.calls.flatten

    assert_includes inputs, "query: hello"
    assert_includes inputs, "query: Ownership in Rust"
  end

  def test_falls_back_to_noise_level_without_titles
    result = calibrate(entries.map { |e| e.merge(title: nil) })

    assert_nil result.relevance
    assert_equal result.noise, result.min_score
  end

  def test_returns_nil_when_nothing_is_indexed
    assert_nil calibrate([])
  end
end
