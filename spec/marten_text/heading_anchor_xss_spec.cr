require "../spec_helper"

# Regression spec for HIGH H3 (renderer.cr `anchor_headings` hook).
#
# Complements `spec/marten_text/xss_spec.cr` by exercising the
# heading-rewrite codepath specifically: a `<script>` tag smuggled
# inside a heading source must not survive to the rendered output,
# because markd's `safe: true` default strips it before the heading
# regex captures the inner HTML the hook will see.
#
# If a future change flips the default to `safe: false`, or if the
# heading hook's contract is widened in a way that lets raw HTML
# through, this spec breaks loudly.
describe MartenText::Renderer do
  describe "heading hook XSS hardening" do
    it "neutralises a <script> tag smuggled inside a heading" do
      html = MartenText::Renderer.render(%(# <script>alert(1)</script>))

      # The `<script>` opening/closing tags must be stripped (markd
      # safe-mode replaces them with a placeholder comment). The
      # `alert(1)` body text may survive as inert text content inside
      # the heading — that's harmless since there's no executable
      # surface left.
      html.downcase.should_not contain "<script"
    end

    it "neutralises a javascript: link smuggled inside a heading" do
      html = MartenText::Renderer.render(%(# [pwn](javascript:alert(1)) header))

      # The link element may or may not render depending on markd's
      # safe-mode handling of `javascript:`; the invariant is that no
      # `javascript:` URL reaches the rendered HTML as an attribute.
      html.should_not contain "javascript:alert"
    end

    it "preserves the default heading-anchor hook output for plain headings" do
      # Sanity: the doc-only H3 contract change must not regress the
      # default hook (the lambda in Configuration that emits
      # `<h1 id="...">text</h1>`).
      html = MartenText::Renderer.render("# Hello World")
      html.should contain %(<h1 id="hello-world">Hello World</h1>)
    end
  end
end
