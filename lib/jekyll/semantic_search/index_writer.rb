# frozen_string_literal: true

require "fileutils"
require "json"
require "sqlite3"

module Jekyll
  module SemanticSearch
    # Writes the search database shipped to the browser.
    #
    #   meta(key, value)                    embedding settings the browser must reuse
    #   documents(id, url, title, date, excerpt, data)
    #   chunks(id, document_id, position, content, embedding)
    class IndexWriter
      SCHEMA_VERSION = 1

      SCHEMA = <<~SQL
        CREATE TABLE meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
        CREATE TABLE documents (
          id INTEGER PRIMARY KEY,
          url TEXT NOT NULL,
          title TEXT,
          date TEXT,
          excerpt TEXT,
          data TEXT
        );
        CREATE TABLE chunks (
          id INTEGER PRIMARY KEY,
          document_id INTEGER NOT NULL REFERENCES documents(id),
          position INTEGER NOT NULL,
          content TEXT,
          embedding BLOB NOT NULL
        );
        CREATE INDEX chunks_document_id ON chunks(document_id);
      SQL

      def initialize(config)
        @config = config
      end

      # entries: [{ url:, title:, date:, excerpt:, data:, chunks: [{ content:, vector: }] }]
      def write(path, entries)
        FileUtils.mkdir_p(File.dirname(path))
        tmp = "#{path}.tmp"
        FileUtils.rm_f(tmp)

        db = SQLite3::Database.new(tmp)
        db.execute_batch(SCHEMA)
        db.transaction do
          write_meta(db, dimensions(entries))
          entries.each_with_index { |entry, id| write_entry(db, id + 1, entry) }
        end
        db.execute("VACUUM")
        db.close
        File.rename(tmp, path)
      ensure
        db&.close unless db&.closed?
        FileUtils.rm_f(tmp)
      end

      private

      def dimensions(entries)
        sizes = entries.flat_map { |e| e[:chunks].map { |c| c[:vector].size } }.uniq
        raise Error, "Embeddings have inconsistent dimensions: #{sizes.inspect}" if sizes.size > 1

        sizes.first || 0
      end

      def write_meta(db, dimensions)
        meta = @config.embedding_signature.merge(
          "schema_version" => SCHEMA_VERSION,
          "dimensions" => dimensions,
          "query_prefix" => @config.query_prefix,
          "plugin_version" => VERSION
        )
        meta.each do |key, value|
          db.execute("INSERT INTO meta (key, value) VALUES (?, ?)", [key, JSON.generate(value)])
        end
      end

      def write_entry(db, id, entry)
        db.execute(
          "INSERT INTO documents (id, url, title, date, excerpt, data) VALUES (?, ?, ?, ?, ?, ?)",
          [id, entry[:url], entry[:title], entry[:date], entry[:excerpt], entry[:data] && JSON.generate(entry[:data])]
        )
        entry[:chunks].each_with_index do |chunk, position|
          db.execute(
            "INSERT INTO chunks (document_id, position, content, embedding) VALUES (?, ?, ?, ?)",
            [id, position, @config.store_content? ? chunk[:content] : nil, SQLite3::Blob.new(Vector.pack(chunk[:vector]))]
          )
        end
      end
    end
  end
end
