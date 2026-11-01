# frozen_string_literal: true

require "test_helper"

class ConfigurationTest < Minitest::Test
  Configuration = Jekyll::SemanticSearch::Configuration
  ConfigurationError = Jekyll::SemanticSearch::ConfigurationError

  def test_defaults_apply_when_section_missing
    config = Configuration.new({})

    assert_predicate config, :enabled?
    assert_equal "Xenova/all-MiniLM-L6-v2", config.model
    assert_equal ["posts"], config.collections
    assert_equal "assets/semantic-search/index.sqlite3", config.database_path
  end

  def test_user_settings_override_defaults
    config = Configuration.new(
      "semantic_search" => {
        "model" => "Xenova/bge-small-en-v1.5",
        "pooling" => "cls",
        "query_prefix" => "query: ",
        "collections" => "notes",
        "output_dir" => "search"
      }
    )

    assert_equal "Xenova/bge-small-en-v1.5", config.model
    assert_equal "cls", config.pooling
    assert_equal "query: ", config.query_prefix
    assert_equal ["notes"], config.collections
    assert_equal "search/index.sqlite3", config.database_path
  end

  def test_can_be_disabled
    refute_predicate Configuration.new("semantic_search" => { "enabled" => false }), :enabled?
  end

  def test_embedding_signature_covers_vector_affecting_settings
    signature = Configuration.new("semantic_search" => { "dtype" => "fp32", "normalize" => false }).embedding_signature

    assert_equal(
      { "model" => "Xenova/all-MiniLM-L6-v2", "dtype" => "fp32", "pooling" => "mean", "normalize" => false },
      signature
    )
  end

  def test_rejects_unknown_dtype
    assert_raises(ConfigurationError) { Configuration.new("semantic_search" => { "dtype" => "fp64" }) }
  end

  def test_rejects_unknown_pooling
    assert_raises(ConfigurationError) { Configuration.new("semantic_search" => { "pooling" => "max" }) }
  end

  def test_rejects_overlap_not_smaller_than_chunk_size
    assert_raises(ConfigurationError) do
      Configuration.new("semantic_search" => { "chunk_size" => 10, "chunk_overlap" => 10 })
    end
  end

  def test_min_score_defaults_to_no_filter
    config = Configuration.new({})

    assert_nil config.min_score
    refute_predicate config, :auto_min_score?
  end

  def test_accepts_numeric_or_auto_min_score
    assert_in_delta 0.3, Configuration.new("semantic_search" => { "min_score" => 0.3 }).min_score
    assert_equal(-1, Configuration.new("semantic_search" => { "min_score" => -1 }).min_score)
    assert_predicate Configuration.new("semantic_search" => { "min_score" => "auto" }), :auto_min_score?
  end

  def test_rejects_invalid_min_score
    [1.5, -2, "high", "0.3", true].each do |value|
      assert_raises(ConfigurationError, value.inspect) { Configuration.new("semantic_search" => { "min_score" => value }) }
    end
  end

  def test_keyword_weight_defaults_to_off_and_accepts_fractions
    assert_equal 0, Configuration.new({}).keyword_weight
    assert_in_delta 0.15, Configuration.new("semantic_search" => { "keyword_weight" => 0.15 }).keyword_weight
  end

  def test_rejects_invalid_keyword_weight
    [-0.1, 1.5, "0.2", nil].each do |value|
      assert_raises(ConfigurationError, value.inspect) do
        Configuration.new("semantic_search" => { "keyword_weight" => value })
      end
    end
  end

  def test_rejects_non_mapping_section
    assert_raises(ConfigurationError) { Configuration.new("semantic_search" => "yes") }
  end
end
