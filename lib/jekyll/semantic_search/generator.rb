# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    RUNTIME_FILES = %w[semantic-search.js search-core.js].freeze

    class << self
      # Builds the embedder used at build time. Override to plug in another
      # backend (it must respond to `embed(texts) -> [[Float]]`).
      attr_writer :embedder_factory

      def embedder_factory
        @embedder_factory ||= ->(config) { InformersEmbedder.new(config) }
      end
    end

    # Registers the browser runtime and the search database with the site.
    class Generator < Jekyll::Generator
      safe true
      priority :lowest

      def generate(site)
        config = Configuration.new(site.config)
        return unless config.enabled?

        RUNTIME_FILES.each { |name| site.static_files << AssetFile.new(site, config.output_dir, name) }
        site.static_files << IndexFile.new(site, config, SemanticSearch.embedder_factory)
      end
    end
  end
end
