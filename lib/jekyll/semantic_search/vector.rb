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
    end
  end
end
