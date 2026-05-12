module MartenText
  # Markdown → HTML pipeline:
  #   1. markd (CommonMark) → HTML.
  #   2. tartrazine syntax-highlight on fenced code blocks.
  #   3. host-supplied `image_wrapper` over every top-level `<img>`.
  #   4. host-supplied `heading_anchor` over every `<h1>`–`<h6>`, with
  #      slug-based IDs deduplicated within the render call.
  #
  # The two host-supplied hooks live on `MartenText.configuration`;
  # see `Configuration`.
  module Renderer
    extend self

    def render(source : String) : String
      cfg = MartenText.configuration
      html = Markd.to_html(source, cfg.markd_options)
      html = highlight_code_blocks(html, cfg.syntax_theme)
      html = wrap_images(html, cfg.image_wrapper)
      html = anchor_headings(html, cfg.heading_anchor)
      html
    end

    # Rewrite `<pre><code class="language-foo">…</code></pre>` blocks via
    # tartrazine. Falls back to the unmodified block if the language isn't
    # recognised or highlighting raises.
    private def highlight_code_blocks(html : String, theme : String) : String
      html.gsub(/<pre><code(?: class="language-([^"]+)")?>(.*?)<\/code><\/pre>/m) do |_match, m|
        lang_str = m[1]?
        lang = (lang_str && !lang_str.empty?) ? lang_str : nil
        raw = decode_entities(m[2])
        highlight_or_passthrough(raw, lang, theme)
      end
    end

    private def highlight_or_passthrough(code : String, lang : String?, theme : String) : String
      return %(<pre><code>#{escape_html(code)}</code></pre>) if lang.nil?

      formatter = Tartrazine::Html.new(theme: Tartrazine.theme(theme), standalone: false, line_numbers: false)
      lexer = Tartrazine.lexer(name: lang)
      formatter.format(code, lexer)
    rescue
      %(<pre><code class="language-#{lang}">#{escape_html(code)}</code></pre>)
    end

    private def wrap_images(html : String, hook : Proc(String, String, String?, String)) : String
      html.gsub(/<img src="([^"]+)" alt="([^"]*)"(?: title="([^"]*)")?\s*\/?>/) do |_match, m|
        url = m[1]
        alt = m[2]
        title = m[3]?
        hook.call(url, alt, title)
      end
    end

    private def anchor_headings(html : String, hook : Proc(String, String, String, String)) : String
      counts = Hash(String, Int32).new(0)
      html.gsub(/<(h[1-6])>(.*?)<\/\1>/m) do |_match, m|
        level = m[1]
        text = m[2]
        base = slug_for(strip_tags(text))
        counts[base] += 1
        id = counts[base] > 1 ? "#{base}-#{counts[base]}" : base
        hook.call(level, text, id)
      end
    end

    private def slug_for(text : String) : String
      s = text.downcase.gsub(/[^a-z0-9]+/, "-").strip('-')
      s.empty? ? "section" : s
    end

    private def strip_tags(html : String) : String
      html.gsub(/<[^>]+>/, "")
    end

    # Exposed (not private) so default hooks in `Configuration` can reuse it.
    def escape_html(s : String) : String
      s.gsub('&', "&amp;").gsub('<', "&lt;").gsub('>', "&gt;").gsub('"', "&quot;")
    end

    private def decode_entities(s : String) : String
      s.gsub("&lt;", "<").gsub("&gt;", ">").gsub("&quot;", "\"").gsub("&#39;", "'").gsub("&amp;", "&")
    end
  end
end
