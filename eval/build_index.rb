# frozen_string_literal: true

# Builds a search index straight from a directory of Markdown files, for sites
# that are impractical to build with Jekyll here (their own plugins and themes).
# Liquid tags are dropped; everything after rendering goes through the plugin's
# own pipeline (TextExtractor, Chunker, embedder, calibration, IndexWriter).
#
#   bundle exec ruby -Ilib eval/build_index.rb SOURCE OUTPUT.sqlite3 [SETTINGS_JSON]
require "json"
require "kramdown"
require "jekyll"
require "jekyll-semantic-search"

source, output, settings_json = ARGV
abort "usage: build_index.rb SOURCE OUTPUT [SETTINGS_JSON]" unless source && output

include Jekyll::SemanticSearch # rubocop:disable Style/MixinUsage

settings = JSON.parse(settings_json || "{}")
config = Configuration.new("semantic_search" => { "min_score" => "auto", "keyword_search" => true }.merge(settings))
chunker = Chunker.new(size: config.chunk_size, overlap: config.chunk_overlap)
cache_dir = File.join(__dir__, "..", "tmp", "eval-cache")
cache = EmbeddingCache.new(File.join(cache_dir, "embeddings.sqlite3"), config.embedding_signature)
embedder = BatchEmbedder.new(InformersEmbedder.new(config), batch_size: config.batch_size, cache: cache)

# SOURCE is a directory (all Markdown files below it) or a glob such as "dir/*.md".
pattern = source.include?("*") ? source : File.join(source, "**", "*.md")
base = pattern[/\A[^*]*/].sub(%r{/[^/]*\z}, "")
documents = Dir.glob(pattern).sort.filter_map do |path|
  raw = File.read(path)
  front, body = raw.start_with?("---") ? raw.split(/^---\s*$/, 3)[1..] : ["", raw]
  data = YAML.safe_load(front.to_s, permitted_classes: [Date, Time]) || {}
  body = body.to_s.gsub(/\{%-?\s*raw\s*-?%\}(.*?)\{%-?\s*endraw\s*-?%\}/m, '\1')
             .gsub(/\{%.*?%\}/m, " ").gsub(/\{\{.*?\}\}/m, " ")
  passages = chunker.split(TextExtractor.extract(Kramdown::Document.new(body).to_html))
  next if passages.empty?

  title = (data["title"] || File.basename(path, ".md")).to_s
  slug = path.delete_prefix(base).delete_prefix("/").delete_suffix(".md")
  [{ url: "/#{slug}/", title: title, date: nil, excerpt: nil, data: {} }, passages]
end

inputs = documents.flat_map do |entry, passages|
  passages.map { |p| "#{config.document_prefix}#{entry[:title]}\n#{p}" }
end
vectors = embedder.embed(inputs).each
entries = documents.map do |entry, passages|
  entry.merge(chunks: passages.map { |p| { content: p, vector: vectors.next } })
end

calibration = MinScoreCalibrator.new(config, embedder).calibrate(entries)
IndexWriter.new(config).write(output, entries, calibration: calibration)
cache.close
warn format("%<n>d documents, %<p>d passages; min_score %<min>.3f (noise %<noise>.3f, titles %<rel>.3f)",
            n: entries.size, p: entries.sum { |e| e[:chunks].size }, min: calibration.min_score,
            noise: calibration.noise, rel: calibration.relevance)
