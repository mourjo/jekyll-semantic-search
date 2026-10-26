# frozen_string_literal: true

require "json"

module Jekyll
  module SemanticSearch
    # {% semantic_search %} emits the runtime configuration and loads the
    # browser module, which fetches the database as soon as the page loads.
    class Tag < Liquid::Tag
      def render(context)
        site = context.registers[:site]
        config = Configuration.new(site.config)
        return "" unless config.enabled?

        base = "#{site.baseurl.to_s.chomp("/")}/#{config.output_dir.delete_prefix("/").chomp("/")}"
        runtime = {
          databaseUrl: "#{base}/#{config.database}",
          transformersUrl: config.transformers_url,
          sqlJsUrl: config.sql_js_url,
          preloadModel: config.preload_model?
        }
        json = JSON.generate(runtime).gsub("</", "<\\/")

        <<~HTML.chomp
          <script type="application/json" id="semantic-search-config">#{json}</script>
          <script type="module" src="#{base}/semantic-search.js"></script>
        HTML
      end
    end
  end
end

Liquid::Template.register_tag("semantic_search", Jekyll::SemanticSearch::Tag)
