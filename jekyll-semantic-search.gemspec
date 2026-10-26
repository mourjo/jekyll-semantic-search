# frozen_string_literal: true

require_relative "lib/jekyll/semantic_search/version"

Gem::Specification.new do |spec|
  spec.name = "jekyll-semantic-search"
  spec.version = Jekyll::SemanticSearch::VERSION
  spec.authors = ["Mourjo Sen"]
  spec.summary = "Client-side semantic search for Jekyll sites."
  spec.description = <<~DESC
    Embeds your Jekyll posts at build time with any Transformers.js-compatible
    ONNX model, stores the vectors in a SQLite database, and ships a browser
    runtime that embeds queries and searches that database entirely client-side.
  DESC
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.1"

  spec.files = Dir["lib/**/*.rb", "assets/**/*", "README.md", "LICENSE"]
  spec.require_paths = ["lib"]

  spec.add_dependency "informers", "~> 1.3"
  spec.add_dependency "jekyll", ">= 3.9", "< 5.0"
  spec.add_dependency "sqlite3", ">= 1.6"
end
