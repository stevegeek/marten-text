require "../spec_helper"

# Regression specs for marten-text-review.md §L3, §L4, and the Phase 4
# follow-up note about entity decoding in the slug pipeline.
#
# §L3 — `slug_for` previously collapsed every non-ASCII heading to
#       `"section"`. The Phase 5 fix swaps the slug regex from
#       `/[^a-z0-9]+/` to `/[^[:alnum:]_]+/`, which keeps Unicode
#       letters and digits via the POSIX class (PCRE-backed, locale-
#       aware in Crystal).
# §L4 — Underscores are now preserved (`# foo_bar` → `id="foo_bar"`),
#       matching how every other static-site generator slugifies.
# §Phase 4 follow-up — `## a < b > c` used to produce `id="a-lt-b-gt-c"`
#       because `slug_for` ran on the entity-bearing text. The fix
#       runs `HTML.unescape` *before* `slug_for(strip_tags(...))`.
describe MartenText::Renderer do
  describe "slug pipeline" do
    it "preserves Japanese characters in heading ids (L3)" do
      html = MartenText::Renderer.render("# こんにちは")
      html.should contain %(<h1 id="こんにちは">)
    end

    it "preserves Cyrillic characters in heading ids (L3)" do
      html = MartenText::Renderer.render("# Привет мир")
      html.should contain %(<h1 id="привет-мир">)
    end

    it "folds emoji to dashes but keeps surrounding alphanumerics (L3)" do
      # `🎉` is neither alnum nor underscore; it folds to `-`, which
      # then strips off the leading position. `party` survives.
      html = MartenText::Renderer.render("# 🎉 party")
      html.should contain %(<h1 id="party">)
    end

    it "preserves underscores in heading ids (L4)" do
      html = MartenText::Renderer.render("# foo_bar")
      html.should contain %(<h1 id="foo_bar">)
    end

    it "decodes HTML entities before slugifying (Phase 4 follow-up)" do
      # markd renders `## a < b > c` with `&lt;` and `&gt;` in the
      # heading inner HTML. Phase 5's HTML.unescape pass converts
      # them back to `<` / `>` which then collapse to `-` via the
      # slug regex — yielding `a-b-c` instead of the pre-Phase-5
      # `a-lt-b-gt-c` artefact.
      html = MartenText::Renderer.render("## a < b > c")
      html.should contain %(<h2 id="a-b-c">)
    end

    it "still falls back to \"section\" for headings with no alnums or underscores" do
      # Pure punctuation / symbols — nothing the slug regex preserves.
      html = MartenText::Renderer.render("# ---")
      html.should contain %(<h1 id="section">)
    end
  end
end
