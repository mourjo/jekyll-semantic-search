# frozen_string_literal: true

# A deterministic, model-free embedder for tests: each lowercase word is hashed
# into one of DIMENSIONS buckets and the resulting vector is L2-normalised.
# test/js/support/hashing-embedder.js implements the same function so the
# browser runtime can be tested against databases built by the Ruby side.
class HashingEmbedder
  DIMENSIONS = 64

  attr_reader :calls

  def initialize
    @calls = []
  end

  def embed(texts)
    @calls << texts
    texts.map { |text| self.class.vector(text) }
  end

  def self.vector(text)
    vector = Array.new(DIMENSIONS, 0.0)
    text.downcase.scan(/[a-z0-9]+/).each do |word|
      hash = word.each_char.reduce(0) { |acc, char| ((acc * 31) + char.ord) % 1_000_003 }
      vector[hash % DIMENSIONS] += 1.0
    end
    norm = Math.sqrt(vector.sum { |v| v * v })
    norm.zero? ? vector : vector.map { |v| v / norm }
  end
end
