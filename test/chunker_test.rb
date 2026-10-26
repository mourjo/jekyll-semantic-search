# frozen_string_literal: true

require "test_helper"

class ChunkerTest < Minitest::Test
  Chunker = Jekyll::SemanticSearch::Chunker

  def words(count) = (1..count).map { |i| "w#{i}" }.join(" ")

  def test_short_text_is_a_single_chunk
    assert_equal ["w1 w2 w3"], Chunker.new(size: 5, overlap: 1).split(words(3))
  end

  def test_windows_overlap
    chunks = Chunker.new(size: 4, overlap: 2).split(words(8))

    assert_equal ["w1 w2 w3 w4", "w3 w4 w5 w6", "w5 w6 w7 w8"], chunks
  end

  def test_last_window_covers_the_tail
    chunks = Chunker.new(size: 4, overlap: 1).split(words(9))

    assert_equal "w7 w8 w9", chunks.last
  end

  def test_empty_text_has_no_chunks
    assert_empty Chunker.new(size: 4, overlap: 1).split("   ")
  end

  def test_rejects_overlap_not_smaller_than_size
    assert_raises(ArgumentError) { Chunker.new(size: 3, overlap: 3) }
  end
end
