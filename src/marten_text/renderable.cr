require "html"

module MartenText
  # Mixin for the host's concrete Markdown row model. Provides:
  #   - `to_html` — render `content` through `MartenText::Renderer`.
  #   - `plain_text` — extract human-readable text from the markdown
  #     *source* (not the rendered HTML), suitable for full-text
  #     indexing, blank-detection, search excerpts, etc.
  #
  # The host model must declare a `content : String` (or nilable
  # variant) field for these to compile. Typical shape:
  #
  #   class Books::Markdown < Marten::Model
  #     include MartenText::Renderable
  #
  #     field :id, :big_int, primary_key: true, auto: true
  #     field :record, :polymorphic, to: [Page, Section], related: :markdowns
  #     field :name, :string, max_size: 64
  #     field :content, :text, blank: true, null: false, default: ""
  #   end
  module Renderable
    # Returns a `Marten::Template::SafeString` **only when markd is
    # configured with `safe: true`** (the default — strips raw HTML and
    # `javascript:`/`vbscript:`/non-image `data:` URLs at parse time).
    # The output is then rewritten through the configured image/heading
    # hooks. Marten templates recognise `SafeString` and skip
    # auto-escaping, so `{{ note.body.to_html }}` renders the HTML
    # directly — no `|safe` filter required.
    #
    # If the host overrides `Configuration#markd_options` with
    # `safe: false` (e.g. to allow trusted-author raw HTML), the output
    # is **no longer guaranteed safe** and this method returns a plain
    # `String` instead of a `SafeString`. The template engine will then
    # auto-escape the value on render, preserving safety by default.
    # Hosts who legitimately want raw HTML in this mode must take
    # explicit responsibility for sanitisation (e.g. run the result
    # through a sanitiser and wrap in `Marten::Template::SafeString`
    # themselves), or use `|safe` in the template — both make the
    # trust handoff visible at the call site.
    #
    # Declared return type is the union `SafeString | String`; the
    # branch is chosen at runtime from `markd_options.safe?`. The
    # rule of thumb is **"SafeString iff sanitised by the pipeline"**;
    # there is no way to launder unsanitised output through this method.
    def to_html : ::Marten::Template::SafeString | ::String
      rendered = ::MartenText::Renderer.render(content || "")
      if ::MartenText.configuration.markd_options.safe?
        ::Marten::Template::SafeString.new(rendered)
      else
        rendered
      end
    end

    # Plain-text rendering of `content`, operating directly on the
    # markdown *source* (not the rendered HTML). Strips:
    #   - fenced and inline code (whole block dropped)
    #   - image syntax (`![alt](url)` → `alt`)
    #   - link syntax (`[text](url)` → `text`)
    #   - inline / block HTML tags
    #   - HTML entities (decoded via `HTML.unescape`, then whitespace
    #     entities like `&nbsp;` collapse with the final `strip`)
    #   - heading markers (`#`, `##`, …), blockquote markers (`>`),
    #     list bullets (`-`, `*`, `+`, `1.`)
    #   - emphasis markers (`*`, `_`)
    #
    # Returns the runs-of-whitespace-collapsed, stripped result.
    # Designed so that `plain_text.strip.empty?` is `true` exactly when
    # the rendered HTML would contain no user-perceptible characters.
    #
    # Why source-strip and not HTML-strip: a naïve HTML-strip regex
    # (`<[^>]+>`) leaks `<script>` / `<style>` body text into the
    # output and breaks on attribute values containing `>`. Operating
    # on the source avoids both classes of bug at lower CPU cost.
    def plain_text : String
      ::MartenText::Renderable.strip_markdown(content || "")
    end

    # Markdown-source → plain-text. Module-method so the same code is
    # available without an instance (e.g. for tests of the stripping
    # behaviour itself). Order of passes matters: code blocks before
    # generic tag/markdown stripping (so their contents are dropped
    # wholesale), entity-decode before whitespace-collapse (so `&nbsp;`
    # collapses).
    def self.strip_markdown(source : String) : String
      s = source

      # 1. Fenced code blocks: ``` ... ``` or ~~~ ... ~~~ (drop the
      #    fence markers + optional info-string / language label on the
      #    opening line, keep the body so a code-only note still reports
      #    `body? == true` and the body text is searchable). The body
      #    text gets the same downstream tag-strip / entity-decode /
      #    whitespace-collapse passes as everything else.
      s = s.gsub(/```[^\n`]*\n?([\s\S]*?)```/m, " \\1 ")
      s = s.gsub(/~~~[^\n~]*\n?([\s\S]*?)~~~/m, " \\1 ")

      # 2. Inline code: `…` (drop the markers, keep the body — usually
      #    short identifier-like text that's fine in a search excerpt).
      s = s.gsub(/`+([^`]*)`+/, "\\1")

      # 3. Images: ![alt](url) → alt. Run BEFORE links so the leading `!`
      #    doesn't get eaten by the link regex.
      s = s.gsub(/!\[([^\]]*)\]\([^)]*\)/, "\\1")

      # 4. Links: [text](url) → text.
      s = s.gsub(/\[([^\]]*)\]\([^)]*\)/, "\\1")

      # 5. Reference-style link/image labels: [text][label] / ![alt][label]
      s = s.gsub(/!?\[([^\]]*)\]\[[^\]]*\]/, "\\1")

      # 6a. Script / style blocks: drop entire element including body
      #     so executable / style source doesn't leak into plain text.
      s = s.gsub(/<script\b[^>]*>[\s\S]*?<\/script>/i, " ")
      s = s.gsub(/<style\b[^>]*>[\s\S]*?<\/style>/i, " ")

      # 6b. Remaining HTML tags (markdown source can contain inline /
      #     block HTML).
      s = s.gsub(/<[^>]*>/, " ")

      # 7. HTML entities (`&nbsp;`, `&amp;`, `&#39;`, `&#x27;`, …).
      s = HTML.unescape(s)

      # 8. ATX heading markers at start of line: `# `, `## `, …
      s = s.gsub(/^[ \t]*\#{1,6}[ \t]+/m, "")

      # 9. Setext heading underlines: line of `=` or `-` (entire line).
      s = s.gsub(/^[ \t]*[=\-]{2,}[ \t]*$/m, " ")

      # 10. Blockquote markers at start of line.
      s = s.gsub(/^[ \t]*>+[ \t]?/m, "")

      # 11. List bullets at start of line: `-`, `*`, `+`, or `N.`.
      s = s.gsub(/^[ \t]*(?:[-*+]|\d+\.)[ \t]+/m, "")

      # 12. Horizontal rules: lines of 3+ `-` / `*` / `_`.
      s = s.gsub(/^[ \t]*(?:[-*_][ \t]*){3,}$/m, " ")

      # 13. Emphasis markers (`**bold**`, `*em*`, `__b__`, `_e_`).
      #     Strip the markers wholesale — content sits between them.
      s = s.gsub(/\*+/, "")
      s = s.gsub(/_+/, "")

      # 14. Collapse runs of whitespace and strip. `String#strip` removes
      #     U+00A0 (NBSP), so `&nbsp;` decoded above becomes blank.
      s.gsub(/\s+/, " ").strip
    end
  end
end
