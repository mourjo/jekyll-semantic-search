# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Vectors are stored as little-endian float32 blobs, the layout the browser
    # reads with `new Float32Array(blob.buffer)` (and the one sqlite-vec uses).
    module Vector
      module_function

      def pack(floats)
        floats.pack("e*").b
      end

      def unpack(blob)
        blob.unpack("e*")
      end

      # Same definition as cosineSimilarity in search-core.js.
      def cosine(a, b)
        dot = norm_a = norm_b = 0.0
        a.each_with_index do |x, i|
          y = b[i]
          dot += x * y
          norm_a += x * x
          norm_b += y * y
        end
        norm_a.zero? || norm_b.zero? ? 0.0 : dot / Math.sqrt(norm_a * norm_b)
      end
    end
  end
end
