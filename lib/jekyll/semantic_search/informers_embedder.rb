# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Runs the configured ONNX model with the informers gem, which mirrors
    # Transformers.js so build-time vectors match the ones computed in the browser.
    class InformersEmbedder
      def initialize(config)
        @config = config
      end

      def embed(texts)
        pipeline.(texts, pooling: @config.pooling, normalize: @config.normalize?)
      end

      private

      def pipeline
        @pipeline ||= begin
          require "informers"
          Jekyll.logger.info "Semantic Search:", "Loading #{@config.model} (#{@config.dtype})"
          Informers.pipeline("embedding", @config.model, dtype: @config.dtype)
        end
      end
    end
  end
end
