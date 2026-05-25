require "../spec_helper"

# Regression specs for marten-text-review.md Phase 5 LOW items:
#
# §L2 — `escape_html` now delegates to `HTML.escape` from the stdlib,
#       which escapes the canonical five entities including `'`.
# §L5 — `Tartrazine.theme(name)` is memoised on a module-level cache
#       so the same fenced code block rendered twice produces
#       identical output without rebuilding the theme.
# §L6 — `highlight_or_passthrough` now uses an explicit `rescue
#       Exception` (with a comment explaining why a narrower class
#       isn't available) instead of bare `rescue`. Behaviour for the
#       unknown-language path is unchanged; this spec verifies it
#       still falls back to a `<pre><code class="language-…">` shape.
describe MartenText::Renderer do
  describe ".escape_html (L2)" do
    it "escapes the canonical five HTML entities including apostrophe" do
      out = MartenText::Renderer.escape_html(%(a & b < c > d " e ' f))
      out.should eq %(a &amp; b &lt; c &gt; d &quot; e &#39; f)
    end

    it "escapes ampersand before any other character to avoid double-escape" do
      MartenText::Renderer.escape_html("&lt;").should eq "&amp;lt;"
    end
  end

  describe "theme cache (L5)" do
    before_each do
      MartenText::Renderer.reset_theme_cache!
    end

    it "renders the same code block identically across calls (memoisation smoke)" do
      src = "```ruby\nputs :hi\n```\n"
      first = MartenText::Renderer.render(src)
      second = MartenText::Renderer.render(src)
      second.should eq first
    end

    it "reset_theme_cache! does not break subsequent renders" do
      src = "```ruby\nputs :hi\n```\n"
      before_reset = MartenText::Renderer.render(src)
      MartenText::Renderer.reset_theme_cache!
      after_reset = MartenText::Renderer.render(src)
      after_reset.should eq before_reset
    end
  end

  describe "unknown-language fallback (L6)" do
    it "renders an unknown language as a plain language-tagged pre/code block" do
      html = MartenText::Renderer.render("```nosuchlang\nx = 1\n```\n")
      html.should contain %(<pre><code class="language-nosuchlang">)
      html.should contain "x = 1"
    end
  end
end
