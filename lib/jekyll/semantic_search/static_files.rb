# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    ASSETS_DIR = File.expand_path("../../../assets/semantic-search", __dir__)

    # A browser runtime file shipped inside the gem, copied into the site.
    class AssetFile < Jekyll::StaticFile
      def initialize(site, dir, name)
        super(site, site.source, dir, name)
      end

      def path
        File.join(ASSETS_DIR, @name)
      end
    end

    # The search database. It has no source file: it is built from the
    # rendered documents when Jekyll writes the site.
    class IndexFile < Jekyll::StaticFile
      def initialize(site, config, embedder_factory)
        super(site, site.source, config.output_dir, config.database)
        @config = config
        @embedder_factory = embedder_factory
      end

      def path
        nil
      end

      def modified?
        true
      end

      def modified_time
        @modified_time ||= Time.now
      end

      def mtime
        modified_time.to_i
      end

      def write(dest)
        started = Time.now
        cache = EmbeddingCache.new(cache_path, @config.embedding_signature) if @config.cache?
        embedder = BatchEmbedder.new(@embedder_factory.call(@config), batch_size: @config.batch_size, cache: cache)
        entries = Indexer.new(@site, @config, embedder).entries
        IndexWriter.new(@config).write(destination(dest), entries)

        Jekyll.logger.info "Semantic Search:", format(
          "Indexed %<docs>d documents (%<chunks>d passages, %<hits>d cached) in %<secs>.1fs",
          docs: entries.size, chunks: entries.sum { |e| e[:chunks].size },
          hits: embedder.cache_hits, secs: Time.now - started
        )
        true
      ensure
        cache&.close
      end

      private

      def cache_path
        @site.in_source_dir(@site.config["cache_dir"] || ".jekyll-cache", "jekyll-semantic-search", "embeddings.sqlite3")
      end
    end
  end
end
