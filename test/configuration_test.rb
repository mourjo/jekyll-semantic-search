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

  def test_rejects_non_mapping_section
    assert_raises(ConfigurationError) { Configuration.new("semantic_search" => "yes") }
  end
end
