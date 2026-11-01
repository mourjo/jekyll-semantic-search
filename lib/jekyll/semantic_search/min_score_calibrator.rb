# frozen_string_literal: true

module Jekyll
  module SemanticSearch
    # Picks a cosine-similarity threshold for `min_score: auto` from the site's
    # own embeddings. Every model has its own baseline score for unrelated text
    # (≈0.1 for MiniLM, ≈0.5 for bge-small, ≈0.75 for gte-small), so a fixed
    # number cannot work across models.
    #
    # Noise: off-topic probe queries are searched against the site and the
    # 90th percentile of their best scores is taken. A percentile, not the
    # maximum, so a few probes that happen to match the blog's topic are ignored.
    #
    # Relevance: each post title is searched, as a query, against its own post,
    # and the median of those scores is taken. Titles are also embedded in every
    # passage, so this overstates what real queries score. The threshold
    # therefore sits only a small step above the noise.
    class MinScoreCalibrator
      PROBES = [
        "weather forecast for tomorrow", "how to change a car tire", "best smartphone camera",
        "history of the roman empire", "stock market investing tips", "learning to play the guitar",
        "quantum physics explained", "how to file taxes", "football world cup results",
        "knitting a wool scarf", "symptoms of the common cold", "cheap flights to paris",
        "how volcanoes erupt", "writing a cover letter", "caring for a pet cat",
        "renaissance painting techniques", "cryptocurrency mining", "planting a lawn",
        "wedding dress shopping", "how bees make honey", "chess opening strategy",
        "repairing a leaky faucet", "learning japanese grammar", "deep sea fish",
        "mortgage interest rates", "yoga for beginners", "ancient egyptian pyramids",
        "how to tie a tie", "electric guitar amplifiers", "saving money on groceries",
        "hello", "thank you", "asdf qwerty", "lorem ipsum dolor sit amet", "what time is it"
      ].freeze

      NOISE_PERCENTILE = 0.9
      # How far from the noise level towards the title level the threshold sits.
      MARGIN = 0.15

      Result = Struct.new(:min_score, :noise, :relevance, keyword_init: true)

      def initialize(config, embedder)
        @config = config
        @embedder = embedder
      end

      # entries: as produced by Indexer#entries. Returns nil when there is nothing to calibrate on.
      def calibrate(entries)
        chunks = entries.flat_map { |e| e[:chunks].map { |c| c[:vector] } }
        return nil if chunks.empty?

        noise = percentile(best_scores(embed_queries(PROBES), chunks), NOISE_PERCENTILE)
        relevance = title_relevance(entries)
        min_score = relevance && relevance > noise ? noise + (MARGIN * (relevance - noise)) : noise
        Result.new(min_score: min_score.round(4), noise: noise.round(4), relevance: relevance&.round(4))
      end

      private

      def embed_queries(texts)
        @embedder.embed(texts.map { |t| "#{@config.query_prefix}#{t}" })
      end

      def best_scores(queries, chunks)
        queries.map { |q| chunks.map { |c| Vector.cosine(q, c) }.max }
      end

      def title_relevance(entries)
        titled = entries.reject { |e| e[:title].to_s.strip.empty? }
        return nil if titled.empty?

        queries = embed_queries(titled.map { |e| e[:title].to_s.strip })
        scores = titled.zip(queries).map { |entry, q| entry[:chunks].map { |c| Vector.cosine(q, c[:vector]) }.max }
        percentile(scores, 0.5)
      end

      def percentile(values, fraction)
        sorted = values.sort
        rank = (sorted.size - 1) * fraction
        low = sorted[rank.floor]
        low + ((sorted[rank.ceil] - low) * (rank - rank.floor))
      end
    end
  end
end
