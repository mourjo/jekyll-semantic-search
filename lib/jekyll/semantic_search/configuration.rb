# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Reads and validates the `semantic_search` section of _config.yml.
    class Configuration
      CONFIG_KEY = "semantic_search"

      DEFAULTS = {
        "enabled" => true,
        # Any Transformers.js-compatible ONNX feature-extraction model on the
        # Hugging Face Hub. The same model is used at build time and in the browser.
        "model" => "Xenova/all-MiniLM-L6-v2",
        "dtype" => "q8",
        "pooling" => "mean",
        "normalize" => true,
        "document_prefix" => "",
        "query_prefix" => "",
        "collections" => ["posts"],
        "chunk_size" => 150,
        "chunk_overlap" => 30,
        "batch_size" => 16,
        "store_content" => true,
        "cache" => true,
        "output_dir" => "assets/semantic-search",
        "database" => "index.sqlite3",
        "transformers_url" => "https://cdn.jsdelivr.net/npm/@huggingface/transformers@4.3.1",
        "sql_js_url" => "https://cdn.jsdelivr.net/npm/sql.js@1.14.2/dist/",
        "preload_model" => true
      }.freeze

      DTYPES = %w[fp32 fp16 q8 int8 uint8 q4 q4f16 bnb4].freeze
      POOLINGS = %w[mean cls].freeze

      attr_reader :settings

      def initialize(site_config)
        user = site_config.fetch(CONFIG_KEY, nil) || {}
        raise ConfigurationError, "`#{CONFIG_KEY}` must be a mapping" unless user.is_a?(Hash)

        @settings = DEFAULTS.merge(user.transform_keys(&:to_s))
        validate!
      end

      DEFAULTS.each_key do |key|
        define_method(key) { @settings[key] }
      end

      def enabled?
        enabled != false
      end

      def normalize?
        normalize != false
      end

      def store_content?
        store_content != false
      end

      def cache?
        cache != false
      end

      def preload_model?
        preload_model != false
      end

      # Site-relative path of the generated SQLite database.
      def database_path
        File.join(output_dir, database)
      end

      # Everything that changes the produced vectors. Used to key the cache and
      # stored in the database so the browser embeds queries identically.
      def embedding_signature
        {
          "model" => model,
          "dtype" => dtype,
          "pooling" => pooling,
          "normalize" => normalize?
        }
      end

      private

      def validate!
        raise ConfigurationError, "`model` must be a non-empty string" if model.to_s.strip.empty?
        raise ConfigurationError, "`dtype` must be one of #{DTYPES.join(", ")}" unless DTYPES.include?(dtype)
        raise ConfigurationError, "`pooling` must be one of #{POOLINGS.join(", ")}" unless POOLINGS.include?(pooling)

        @settings["collections"] = Array(collections).map(&:to_s)
        validate_positive_integer!("chunk_size")
        validate_positive_integer!("batch_size")
        return if chunk_overlap.is_a?(Integer) && chunk_overlap >= 0 && chunk_overlap < chunk_size

        raise ConfigurationError, "`chunk_overlap` must be an integer in [0, chunk_size)"
      end

      def validate_positive_integer!(key)
        value = @settings[key]
        return if value.is_a?(Integer) && value.positive?

        raise ConfigurationError, "`#{key}` must be a positive integer"
      end
    end
  end
end
