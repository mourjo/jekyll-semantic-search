# frozen_string_literal: true

require "test_helper"

class TextExtractorTest < Minitest::Test
  def extract(html) = Jekyll::SemanticSearch::TextExtractor.extract(html)

  def test_strips_tags_and_decodes_entities
    assert_equal "Fish & chips are great", extract("<p>Fish &amp; <em>chips</em> are great</p>")
  end

  def test_drops_scripts_styles_and_comments
    html = "<style>p{}</style><p>Hello</p><script>alert(1)</script><!-- hidden -->"

    assert_equal "Hello", extract(html)
  end

  def test_block_elements_become_line_breaks
    assert_equal "Title\nFirst\nSecond", extract("<h1>Title</h1><ul><li>First</li><li>Second</li></ul>")
  end

  def test_collapses_whitespace
    assert_equal "a b\nc", extract("  a \t  b  <br>   c  ")
  end

  def test_handles_nil
    assert_equal "", extract(nil)
  end
end
