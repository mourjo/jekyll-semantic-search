# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Splits text into overlapping word windows so long posts fit within the
    # model's context and each passage gets its own embedding.
    class Chunker
      def initialize(size:, overlap:)
        raise ArgumentError, "overlap must be smaller than size" unless overlap < size

        @size = size
        @step = size - overlap
      end

      def split(text)
        words = text.to_s.split
        return [] if words.empty?

        chunks = []
        start = 0
        loop do
          chunks << words[start, @size].join(" ")
          break if start + @size >= words.length

          start += @step
        end
        chunks
      end
    end
  end
end
