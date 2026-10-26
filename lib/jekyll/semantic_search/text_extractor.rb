# frozen_string_literal: true

require "cgi"

module Jekyll
  module SemanticSearch
    # Turns rendered HTML into plain text suitable for embedding.
    module TextExtractor
      DROPPED_ELEMENTS = /<(script|style|noscript|template|svg)\b[^>]*>.*?<\/\1\s*>/mi
      COMMENTS = /<!--.*?-->/m
      BLOCK_TAGS = /<\/?(p|div|br|li|ul|ol|h[1-6]|pre|blockquote|tr|table|section|article|hr)\b[^>]*>/i
      TAGS = /<[^>]+>/

      module_function

      def extract(html)
        text = html.to_s
          .gsub(COMMENTS, " ")
          .gsub(DROPPED_ELEMENTS, " ")
          .gsub(BLOCK_TAGS, "\n")
          .gsub(TAGS, "")
        CGI.unescapeHTML(text).gsub(/[ \t ]+/, " ").gsub(/\s*\n\s*/, "\n").strip
      end
    end
  end
end
