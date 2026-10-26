# frozen_string_literal: true

# Builds a search index with HashingEmbedder for the JavaScript tests:
#   bundle exec ruby -Ilib -Itest test/support/build_index.rb OUTPUT
require "jekyll-semantic-search"
require "support/hashing_embedder"

POSTS = [
  { url: "/bread/", title: "Baking sourdough bread", tags: ["baking"],
    passages: ["Feed the sourdough starter with flour and water", "Bake the loaf in a hot dutch oven"] },
  { url: "/rust/", title: "Ownership in Rust", tags: [],
    passages: ["The borrow checker enforces ownership at compile time"] },
  { url: "/garden/", title: "Growing tomatoes", tags: ["garden"],
    passages: ["Tomatoes need sun water and support stakes"] }
].freeze

config = Jekyll::SemanticSearch::Configuration.new("semantic_search" => { "query_prefix" => "query: " })
entries = POSTS.map do |post|
  {
    url: post[:url], title: post[:title], date: "2026-01-01T00:00:00+00:00", excerpt: post[:passages].first,
    data: { "tags" => post[:tags] },
    chunks: post[:passages].map { |p| { content: p, vector: HashingEmbedder.vector(p) } }
  }
end
Jekyll::SemanticSearch::IndexWriter.new(config).write(ARGV.fetch(0), entries)
