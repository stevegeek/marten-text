require "html"
require "uri"

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

    # Memoised `Tartrazine::Theme` cache, keyed by theme name. Building a
    # theme via `Tartrazine.theme(name)` parses an XML style document and
    # allocates a non-trivial Theme tree; doing that per fenced code
    # block on a content-heavy page costs real CPU. We populate this on
    # first use and reuse for subsequent renders.
    #
    # Concurrency model: writes here are intended to happen during the
    # configure-once-at-boot pattern, after which the cache is
    # read-only. A race during simultaneous first-uses would at worst
    # build the same theme twice — harmless. If a host needs to clear
    # the cache (spec isolation, dynamic theme swap), use
    # `Renderer.reset_theme_cache!`.
    @@theme_cache = {} of String => Tartrazine::Theme

    # Renders parsed markdown HTML. Returns a plain `String` (not a
    # `Marten::Template::SafeString`) — the public-facing wrapper is
    # `Renderable#to_html`, which is responsible for promoting the
    # output to a SafeString once the full pipeline has run. Keep this
    # method returning `String` so internal callers can post-process
    # without unwrapping; the trust-boundary promotion happens exactly
    # once, at the `Renderable` layer.
    def render(source : String) : String
      cfg = MartenText.configuration
      html = Markd.to_html(source, cfg.markd_options)
      html = highlight_code_blocks(html, cfg.syntax_theme)
      html = wrap_images(html, cfg.image_wrapper)
      html = anchor_headings(html, cfg.heading_anchor)
      html
    end

    # Clears the memoised theme cache. Intended for spec isolation
    # (each example starts from a clean cache) and for hosts that
    # want to swap `syntax_theme` mid-process. Not part of the
    # day-to-day API.
    def reset_theme_cache! : Nil
      @@theme_cache.clear
    end

    # Returns a `Tartrazine::Theme` for `name`, building and caching
    # it on first use.
    private def cached_theme(name : String) : Tartrazine::Theme
      cached = @@theme_cache[name]?
      return cached if cached
      built = Tartrazine.theme(name)
      @@theme_cache[name] = built
      built
    end

    # =======================================================================
    # MARKD OUTPUT-SHAPE COUPLING
    #
    # The three `gsub` passes below (`highlight_code_blocks`, `wrap_images`,
    # `anchor_headings`) are post-hoc regex rewrites of markd's rendered
    # HTML. They are tightly coupled to markd's *exact* output shape:
    # attribute order, attribute quoting style, the `>` (NOT ` />`)
    # self-closing form for `<img>`, and the inter-tag whitespace markd
    # emits between block elements.
    #
    # Verified against the Markd version currently locked in `shard.lock`
    # (Markd `~> 0.5`). The exact substrings each regex targets:
    #
    #   * `highlight_code_blocks` expects
    #         `<pre><code class="language-LANG">CODE</code></pre>`
    #     for fenced code with a language, and
    #         `<pre><code>CODE</code></pre>`
    #     for fenced code without one. `CODE` is HTML-escaped per
    #     CommonMark: `&lt; &gt; &quot; &amp;` and (depending on markd
    #     version) numeric entities like `&#39;` or `&#x27;`. We round-trip
    #     via `HTML.unescape` so the tartrazine lexer sees raw source.
    #
    #   * `wrap_images` expects
    #         `<img src="URL" alt="ALT">`            (no title)
    #         `<img src="URL" alt="ALT" title="T">`  (with title)
    #     with attributes in exactly that order, double-quoted, and the
    #     non-self-closing form. `ALT` / `TITLE` arrive already
    #     HTML-escaped; `URL` is markd-URL-encoded (but NOT
    #     scheme-validated). The trailing `\s*\/?>` tolerates either form
    #     if markd ever switches.
    #
    #     Phase 1 audit-trail edge case: with `safe: true`, an unsafe URL
    #     like `![evil](javascript:alert(1))` produces oddly-quoted
    #     output (`<p><img src="" alt=""evil" /></p>` — note the empty
    #     `src=""` and the stray quote inside the alt-text). The image
    #     regex requires a non-empty `src="..."` capture, so it no-ops
    #     on these — harmless visually because the markup is already
    #     dead, but worth knowing if M5 is ever refactored.
    #
    #   * `anchor_headings` expects `<hN>INNER</hN>` for N = 1..6 with
    #     no attributes on the opening tag. `INNER` is markd's rendered
    #     inline HTML (`<em>`, `<strong>`, `<code>`, `<a>` plus literal
    #     text) and is HTML-escaped where appropriate; markd never emits
    #     bare `<` or `>` inside heading text.
    #
    # If markd's output drifts (a future version adds `loading="lazy"` to
    # images, reorders attributes, adds heading attributes, etc.) these
    # passes will silently no-op. Regression specs in
    # `spec/marten_text/markd_shape_spec.cr` lock in the exact shapes so
    # drift surfaces as a spec failure rather than missing markup.
    #
    # Follow-up direction: the sturdy fix is a `Markd::Renderer`
    # subclass that emits the final `<pre><code>` / `<img>` / `<hN>`
    # shapes directly, eliminating the regex layer. Substantial
    # refactor — tracked in SHARD_REVIEWS_TRACKING.md, not done in
    # Phase 4.
    # =======================================================================

    # Rewrite `<pre><code class="language-foo">…</code></pre>` blocks via
    # tartrazine. Falls back to the unmodified block if the language isn't
    # recognised or highlighting raises.
    private def highlight_code_blocks(html : String, theme : String) : String
      html.gsub(/<pre><code(?: class="language-([^"]+)")?>(.*?)<\/code><\/pre>/m) do |_match, match_data|
        lang_str = match_data[1]?
        lang = (lang_str && !lang_str.empty?) ? lang_str : nil
        raw = HTML.unescape(match_data[2])
        highlight_or_passthrough(raw, lang, theme)
      end
    end

    # Tartrazine raises bare `Exception` (no subclasses defined in the
    # shard, see `lib/tartrazine/src/lexer.cr` / `styles.cr`) for
    # "Unknown lexer: …", "Theme not found", and friends — every
    # failure mode that should degrade to an unhighlighted
    # `<pre><code>` fallback. The rescue below catches `Exception`
    # *narrowly intentionally*: catching `KeyError` alone misses the
    # unknown-lexer path (it's wrapped in a fresh `Exception.new`),
    # and a more specific class would let unknown languages surface
    # as 500s. If tartrazine ever grows a typed error hierarchy,
    # tighten this to that hierarchy plus `KeyError`.
    private def highlight_or_passthrough(code : String, lang : String?, theme : String) : String
      return %(<pre><code>#{escape_html(code)}</code></pre>) if lang.nil?

      formatter = Tartrazine::Html.new(theme: cached_theme(theme), standalone: false, line_numbers: false)
      lexer = Tartrazine.lexer(name: lang)
      formatter.format(code, lexer)
    rescue Exception
      %(<pre><code class="language-#{lang}">#{escape_html(code)}</code></pre>)
    end

    private def wrap_images(html : String, hook : Proc(String, String, String?, String)) : String
      html.gsub(/<img src="([^"]+)" alt="([^"]*)"(?: title="([^"]*)")?\s*\/?>/) do |_match, match_data|
        url = match_data[1]
        alt = match_data[2]
        title = match_data[3]?
        hook.call(url, alt, title)
      end
    end

    # TRUST BOUNDARY for `heading_anchor` hook callers.
    #
    # The hook receives `(level, text, id)` where `text` is the
    # *post-markd HTML* of the heading body — NOT plain text. With the
    # default `markd_options.safe = true`, markd strips raw `<script>`
    # tags, event handlers, and `javascript:`/`vbscript:` URLs *before*
    # the heading regex sees them, so `text` is sanitised against the
    # classic XSS vectors and is safe to interpolate verbatim inside a
    # heading tag (this is what the default hook does).
    #
    # However `text` still contains markd's *allowed* inline HTML —
    # `<em>`, `<strong>`, `<code>`, `<a href="...">`, etc. — emitted by
    # markd from markdown source like `# *bold* heading`. Hooks that
    # want a plain-text rendering of the heading must strip tags
    # themselves; hooks that build attribute values from `text` must
    # HTML-escape it (it contains literal `<` / `>` / `"`).
    #
    # If the host opts in to `markd_options.safe = false`, the input
    # `text` is no longer sanitised and the hook becomes an XSS sink.
    # Hosts that flip this MUST run their own sanitiser.
    private def anchor_headings(html : String, hook : Proc(String, String, String, String)) : String
      counts = Hash(String, Int32).new(0)
      html.gsub(/<(h[1-6])>(.*?)<\/\1>/m) do |_match, match_data|
        level = match_data[1]
        text = match_data[2]
        # Decode entities before slugifying so a heading like
        # `## a < b > c` (which markd renders with `&lt;` / `&gt;` in
        # the inner HTML) doesn't produce a slug of `a-lt-b-gt-c`.
        # `text` itself is passed through to the hook *un-decoded* so
        # the hook still receives the same markd-escaped HTML it
        # always did — the decode is only for slug computation.
        base = slug_for(HTML.unescape(strip_tags(text)))
        counts[base] += 1
        id = counts[base] > 1 ? "#{base}-#{counts[base]}" : base
        hook.call(level, text, id)
      end
    end

    # Computes an HTML id from heading text. Preserves Unicode letters
    # / digits (via the POSIX `[:alnum:]` class, which is
    # locale-aware in Crystal's PCRE-backed regex) and underscores —
    # so `# こんにちは`, `# Привет`, and `# foo_bar` all produce
    # meaningful ids instead of collapsing to `"section"`. Everything
    # else (punctuation, whitespace, emoji, control chars) is folded
    # to `-`. Falls back to `"section"` if the input has no
    # alphanumerics or underscores at all.
    private def slug_for(text : String) : String
      s = text.downcase.gsub(/[^[:alnum:]_]+/, "-").strip('-')
      s.empty? ? "section" : s
    end

    private def strip_tags(html : String) : String
      html.gsub(/<[^>]+>/, "")
    end

    # HTML-escape `s` so it is safe to interpolate inside element
    # bodies or double-quoted / single-quoted attribute values.
    # Escapes `& < > " '` — the canonical "five named entities" set,
    # equivalent to OWASP's recommended HTML-context output encoding.
    #
    # Intentionally public: this is the sanitisation primitive hosts
    # need when writing custom `image_wrapper` / `heading_anchor`
    # hooks (or any other code that interpolates user-controlled
    # text into HTML). See `Configuration.default_image_wrapper`
    # for the in-shard caller and the README for the host-side
    # recipe.
    #
    # Delegates to `HTML.escape` from the Crystal stdlib so the
    # entity set stays in sync with any future stdlib widening
    # (currently `& < > " '` → `&amp; &lt; &gt; &quot; &#39;`).
    def escape_html(s : String) : String
      HTML.escape(s)
    end
  end
end
