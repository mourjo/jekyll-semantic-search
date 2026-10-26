# frozen_string_literal: true

# Embeds texts with the real build-time embedder so the JavaScript model tests
# can compare its vectors with Transformers.js. Reads
# {"settings": {...semantic_search settings...}, "texts": [...]} as JSON on
# stdin and writes the vectors as JSON on stdout.

require "json"
require "jekyll"
require "jekyll-semantic-search"

Jekyll.logger.log_level = :error # keep stdout for the JSON

input = JSON.parse($stdin.read)
config = Jekyll::SemanticSearch::Configuration.new("semantic_search" => input.fetch("settings"))
vectors = Jekyll::SemanticSearch::InformersEmbedder.new(config).embed(input.fetch("texts"))
$stdout.write(JSON.generate(vectors.map { |v| v.map(&:to_f) }))
