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

  def keyword(value)
    Configuration.new("semantic_search" => { "keyword_search" => value })
  end

  def test_keyword_search_is_off_by_default
    config = Configuration.new({})

    refute_predicate config, :keyword_search?
    refute_predicate config, :calibrate?
    assert_equal Configuration::KEYWORD_DEFAULTS, config.keyword_search
  end

  def test_keyword_search_true_uses_defaults
    config = keyword(true)

    assert_predicate config, :keyword_search?
    assert_predicate config, :calibrate?
    assert_equal Configuration::KEYWORD_DEFAULTS.merge("enabled" => true), config.keyword_search
  end

  def test_keyword_search_mapping_enables_and_overrides
    settings = keyword("weight" => 0.5, "min_score" => 0.6, :typo_tolerance => false).keyword_search

    assert settings["enabled"]
    assert_in_delta 0.5, settings["weight"]
    assert_in_delta 0.6, settings["min_score"]
    refute settings["typo_tolerance"]
    assert_in_delta 1.2, settings["k1"]
  end

  def test_keyword_search_mapping_can_stay_disabled
    refute_predicate keyword("enabled" => false, "weight" => 0.5), :keyword_search?
    refute_predicate keyword(nil), :keyword_search?
  end

  def test_rejects_invalid_keyword_search
    [
      "yes", { "weight" => 1.5 }, { "weight" => "0.2" }, { "min_score" => -0.1 }, { "min_score" => nil }, { "b" => 2 },
      { "k1" => 0 }, { "stemming" => "yes" }, { "enabled" => nil }, { "fuzzy" => true }
    ].each do |value|
      assert_raises(ConfigurationError, value.inspect) { keyword(value) }
    end
  end

  def test_old_keyword_weight_points_to_keyword_search
    error = assert_raises(ConfigurationError) { Configuration.new("semantic_search" => { "keyword_weight" => 0.3 }) }

    assert_match(/keyword_search/, error.message)
  end

  def test_rejects_non_mapping_section
    assert_raises(ConfigurationError) { Configuration.new("semantic_search" => "yes") }
  end
end
