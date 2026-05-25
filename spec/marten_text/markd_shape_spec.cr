require "../spec_helper"

# Regression specs for MED M5 (the three post-hoc gsub passes in
# `Renderer` are tightly coupled to markd's exact output shape).
#
# Each spec below pins one shape that, if markd's output drifts (a
# `loading="lazy"` is added to images, the heading tag gains an
# attribute, the fenced code-block class moves to a wrapper element,
# etc.), will cause the corresponding `gsub` to silently no-op and the
# rendered output to lose the marten-text rewrite. Failing here is the
# signal to either bump the Markd version constraint and update the
# regex, or migrate to a `Markd::Renderer` subclass (see the doc
# block in renderer.cr above `highlight_code_blocks`).
describe MartenText::Renderer do
  describe "markd output-shape drift detectors" do
    it "highlight_code_blocks pass: <pre><code class=\"language-...\"> shape (M5)" do
      # We render fenced code with a known language and assert that
      # tartrazine *did* transform the output (it would not if the
      # regex no-op'd because the markd shape changed).
      html = MartenText::Renderer.render("```ruby\nputs :hi\n```\n")

      # Tartrazine emits class-bearing <span>s inside the <pre>. Markd
      # alone produces just a bare <pre><code>...</code></pre>. The
      # presence of <span class= confirms the highlighter pass ran.
      html.should contain "<pre"
      html.should contain "<span class="
    end

    it "wrap_images pass: <img src=\"...\" alt=\"...\"> attribute order (M5)" do
      # The image hook should be called exactly once. If markd reorders
      # to `alt` before `src` (or adds an attribute between them), the
      # regex no-ops and the hook never fires.
      seen = [] of String
      MartenText.configure do |c|
        c.image_wrapper = ->(url : String, alt : String, _title : String?) {
          seen << "#{url}|#{alt}"
          %(<figure data-marker="hooked"><img src="#{url}" alt="#{alt}"></figure>)
        }
      end

      html = MartenText::Renderer.render(%(![cat](https://x/y.png)))
      seen.size.should eq 1
      seen[0].should eq "https://x/y.png|cat"
      html.should contain %(data-marker="hooked")
    end

    it "anchor_headings pass: <h2>...</h2> with `<`/`>` literals in text (M5)" do
      # markd escapes `<` and `>` inside heading text to `&lt;` and
      # `&gt;`. The heading regex matches `<h2>` opening + `</h2>`
      # closing with no attributes; if markd ever adds attributes to
      # the opening tag, the regex no-ops.
      seen = [] of {String, String, String}
      MartenText.configure do |c|
        c.heading_anchor = ->(level : String, text : String, id : String) {
          seen << {level, text, id}
          %(<#{level} data-id="#{id}">#{text}</#{level}>)
        }
      end

      html = MartenText::Renderer.render("## a < b > c")

      seen.size.should eq 1
      seen[0][0].should eq "h2"
      # text is the post-markd inner HTML: `<` and `>` arrive escaped.
      # The hook still receives the markd-escaped form (the entity-
      # decode happens *only* for slug computation, not for the text
      # passed to the hook).
      seen[0][1].should contain "&lt;"
      seen[0][1].should contain "&gt;"
      # Slug pipeline now runs `HTML.unescape` before `slug_for`, so
      # `&lt;` / `&gt;` decode to `<` / `>` and then collapse to `-`
      # via the slug regex — yielding a meaningful `a-b-c` id instead
      # of the historical `a-lt-b-gt-c` artefact (Phase 5).
      seen[0][2].should eq "a-b-c"
      html.should contain %(<h2 data-id="a-b-c">)
    end
  end
end
