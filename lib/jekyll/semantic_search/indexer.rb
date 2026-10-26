# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Collects rendered documents from the site, chunks and embeds them.
    class Indexer
      EXCERPT_LENGTH = 280

      def initialize(site, config, embedder)
        @site = site
        @config = config
        @embedder = embedder
        @chunker = Chunker.new(size: config.chunk_size, overlap: config.chunk_overlap)
      end

      def documents
        @config.collections.flat_map do |label|
          collection = @site.collections[label]
          collection ? collection.docs.select { |doc| indexable?(doc) } : []
        end
      end

      def entries
        pending = documents.filter_map do |doc|
          passages = @chunker.split(TextExtractor.extract(doc.content))
          next if passages.empty?

          [doc, passages]
        end

        inputs = pending.flat_map { |doc, passages| passages.map { |p| embedding_input(doc, p) } }
        vectors = @embedder.embed(inputs).each

        pending.map do |doc, passages|
          entry_for(doc).merge(chunks: passages.map { |p| { content: p, vector: vectors.next } })
        end
      end

      private

      def indexable?(doc)
        doc.data["semantic_search"] != false && doc.data["published"] != false && doc.write?
      end

      # The title is repeated in every passage so each one carries the topic of the post.
      def embedding_input(doc, passage)
        title = doc.data["title"].to_s.strip
        body = title.empty? ? passage : "#{title}\n#{passage}"
        "#{@config.document_prefix}#{body}"
      end

      def entry_for(doc)
        {
          url: "#{@site.baseurl.to_s.chomp("/")}#{doc.url}",
          title: doc.data["title"],
          date: doc.date&.iso8601,
          excerpt: excerpt(doc),
          data: { "tags" => doc.data["tags"], "categories" => doc.data["categories"] }.reject { |_, v| v.nil? || v.empty? }
        }
      end

      def excerpt(doc)
        text = TextExtractor.extract(doc.data["excerpt"].to_s).tr("\n", " ")
        text.length > EXCERPT_LENGTH ? "#{text[0, EXCERPT_LENGTH].rstrip}…" : text
      end
    end
  end
end
