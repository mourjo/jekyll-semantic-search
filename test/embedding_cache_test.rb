# frozen_string_literal: true

require "test_helper"
require "support/hashing_embedder"

class EmbeddingCacheTest < Minitest::Test
  EmbeddingCache = Jekyll::SemanticSearch::EmbeddingCache
  BatchEmbedder = Jekyll::SemanticSearch::BatchEmbedder

  SIGNATURE = { "model" => "m", "dtype" => "q8", "pooling" => "mean", "normalize" => true }.freeze

  def setup
    @dir = Dir.mktmpdir
    @path = File.join(@dir, "nested", "cache.sqlite3")
  end

  def teardown
    FileUtils.rm_rf(@dir)
  end

  def test_round_trips_vectors_as_float32
    cache = EmbeddingCache.new(@path, SIGNATURE)
    cache.store_all("hello" => [0.5, -0.25, 1.0])

    assert_equal({ "hello" => [0.5, -0.25, 1.0] }, cache.fetch_all(%w[hello missing]))
  ensure
    cache&.close
  end

  def test_entries_are_scoped_to_the_embedding_signature
    EmbeddingCache.new(@path, SIGNATURE).tap { |c| c.store_all("hello" => [1.0]) }.close
    other = EmbeddingCache.new(@path, SIGNATURE.merge("model" => "other"))

    assert_empty other.fetch_all(["hello"])
  ensure
    other&.close
  end

  def test_batch_embedder_batches_and_preserves_order
    embedder = HashingEmbedder.new
    batcher = BatchEmbedder.new(embedder, batch_size: 2)
    texts = %w[alpha beta gamma alpha]

    vectors = batcher.embed(texts)

    assert_equal [%w[alpha beta], %w[gamma]], embedder.calls
    assert_equal texts.map { |t| HashingEmbedder.vector(t) }, vectors
  end

  def test_batch_embedder_only_computes_cache_misses
    cache = EmbeddingCache.new(@path, SIGNATURE)
    BatchEmbedder.new(HashingEmbedder.new, batch_size: 8, cache: cache).embed(%w[alpha beta])

    embedder = HashingEmbedder.new
    batcher = BatchEmbedder.new(embedder, batch_size: 8, cache: cache)
    batcher.embed(%w[alpha gamma beta])

    assert_equal [%w[gamma]], embedder.calls
    assert_equal 2, batcher.cache_hits
    assert_equal 1, batcher.computed
  ensure
    cache&.close
  end
end
