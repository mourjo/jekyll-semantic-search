# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Runs the configured ONNX model with the informers gem, which mirrors
    # Transformers.js so build-time vectors match the ones computed in the browser.
    class InformersEmbedder
      # The outputs the Transformers.js feature-extraction pipeline pools, in
      # the order it looks for them.
      POOLED_OUTPUTS = %w[last_hidden_state logits token_embeddings].freeze

      def initialize(config)
        @config = config
      end

      def embed(texts)
        pipeline.(texts, pooling: @config.pooling, normalize: @config.normalize?, model_output: model_output)
      end

      private

      def pipeline
        @pipeline ||= begin
          require "informers"
          Jekyll.logger.info "Semantic Search:", "Loading #{@config.model} (#{@config.dtype})"
          load_pipeline
        end
      end

      def load_pipeline(retried: false)
        Informers.pipeline("embedding", @config.model, dtype: @config.dtype)
      rescue OnnxRuntime::Error => e
        # informers only fetches a model's external weights file when ONNX
        # Runtime reports it as "No such file or directory", which newer
        # versions word differently, so fetch it here and try again.
        raise if retried || !e.message.include?(".onnx_data")

        Informers::Utils::Hub.get_model_file(@config.model, external_data_file)
        load_pipeline(retried: true)
      end

      def external_data_file
        suffix = Informers::Utils::DEFAULT_DTYPE_SUFFIX_MAPPING.fetch(@config.dtype.to_sym)
        "onnx/model#{suffix}.onnx_data"
      end

      # Models with several outputs (e.g. EmbeddingGemma's last_hidden_state
      # and sentence_embedding) need one picked, the same way the browser does.
      def model_output
        return @model_output if defined?(@model_output)

        names = pipeline.instance_variable_get(:@model).instance_variable_get(:@session).outputs.map { |o| o[:name] }
        @model_output = names.size > 1 ? POOLED_OUTPUTS.find { |n| names.include?(n) } : nil
      end
    end
  end
end
