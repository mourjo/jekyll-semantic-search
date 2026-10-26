# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "sqlite3"

module Jekyll
  module SemanticSearch
    # Persists embeddings between builds, keyed by the embedding settings and
    # the exact input text, so `jekyll serve` only embeds what changed.
    class EmbeddingCache
      def initialize(path, signature)
        FileUtils.mkdir_p(File.dirname(path))
        @db = SQLite3::Database.new(path)
        @db.execute("CREATE TABLE IF NOT EXISTS embeddings (key TEXT PRIMARY KEY, vector BLOB NOT NULL)")
        @namespace = JSON.generate(signature.sort.to_h)
      end

      def fetch_all(texts)
        texts.each_with_object({}) do |text, found|
          row = @db.get_first_row("SELECT vector FROM embeddings WHERE key = ?", [key(text)])
          found[text] = Vector.unpack(row.first) if row
        end
      end

      def store_all(pairs)
        @db.transaction do
          pairs.each do |text, vector|
            @db.execute(
              "INSERT OR REPLACE INTO embeddings (key, vector) VALUES (?, ?)",
              [key(text), SQLite3::Blob.new(Vector.pack(vector))]
            )
          end
        end
      end

      def close
        @db.close
      end

      private

      def key(text)
        Digest::SHA256.hexdigest("#{@namespace}\0#{text}")
      end
    end

    # Wraps an embedder with batching and an optional cache.
    class BatchEmbedder
      attr_reader :cache_hits, :computed

      def initialize(embedder, batch_size:, cache: nil)
        @embedder = embedder
        @batch_size = batch_size
        @cache = cache
        @cache_hits = 0
        @computed = 0
      end

      def embed(texts)
        known = @cache ? @cache.fetch_all(texts.uniq) : {}
        missing = texts.uniq - known.keys
        fresh = {}
        missing.each_slice(@batch_size) do |batch|
          vectors = @embedder.embed(batch)
          batch.zip(vectors).each { |text, vector| fresh[text] = vector.map(&:to_f) }
        end
        @cache&.store_all(fresh)

        @cache_hits += texts.size - missing.size
        @computed += missing.size
        all = known.merge(fresh)
        texts.map { |text| all.fetch(text) }
      end
    end
  end
end
