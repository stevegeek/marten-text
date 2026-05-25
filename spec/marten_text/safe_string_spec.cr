require "../spec_helper"

# Regression specs for post-fix re-review R1 and R2.
#
# R1 — `Renderable#to_html` must return a `Marten::Template::SafeString`
#      (not a bare `String`) when markd is configured with `safe: true`,
#      so templates can drop `|safe` and so a future revert to
#      `: ::String` is caught loudly. Phase 2 introduced the SafeString
#      promotion; the re-reviewer's mutation test showed no spec caught
#      the regression. This spec closes that gap.
#
# R2 — When the host opts in to `markd_options.safe = false`, `to_html`
#      must NOT wrap the (potentially unsanitised) output in
#      `SafeString` — that would tell the template engine to skip
#      escaping and turn any author-supplied raw HTML into an XSS sink.
#      Instead it returns a plain `String`, which the template engine
#      auto-escapes by default. Hosts who legitimately want raw HTML in
#      that mode must sanitise + wrap explicitly.
describe MartenText::Renderable do
  describe "#to_html return-type contract" do
    it "returns a Marten::Template::SafeString when markd_options.safe? is true (R1)" do
      note = Note.create!(title: "r1-safe-default")
      note.body = "# hello"

      # Default configuration has `safe: true` (see Configuration#markd_options).
      MartenText.configuration.markd_options.safe?.should be_true

      result = note.body.to_html
      result.should be_a(::Marten::Template::SafeString)

      # The wrapped value's to_s matches the renderer output. We
      # compare against MartenText::Renderer.render directly so the
      # spec doesn't depend on markd's exact byte-for-byte HTML shape.
      expected = ::MartenText::Renderer.render(note.body.content || "")
      result.to_s.should eq expected
      result.to_s.should contain "<h1"
      result.to_s.should contain "hello"
    end

    it "returns a plain String (NOT SafeString) when markd_options.safe? is false (R2)" do
      # Host opts in to raw-HTML / trusted-author mode. Even though
      # markd no longer strips raw HTML, marten-text refuses to
      # launder the output: the value comes back as a bare String so
      # the template engine's auto-escape kicks in by default.
      MartenText.configure do |c|
        c.markd_options = ::Markd::Options.new(smart: true, safe: false)
      end
      MartenText.configuration.markd_options.safe?.should be_false

      note = Note.create!(title: "r2-unsafe")
      note.body = "<script>alert(1)</script>"

      result = note.body.to_html

      # The critical contract: NOT a SafeString.
      result.should_not be_a(::Marten::Template::SafeString)
      result.should be_a(::String)

      # And the rendered content equals the renderer output (raw, since
      # markd is in safe: false mode the <script> survives — which is
      # exactly why we don't wrap it: the template engine will escape
      # it before output).
      expected = ::MartenText::Renderer.render(note.body.content || "")
      result.to_s.should eq expected
    end

    it "round-trips correctly: SafeString wrapped value equals renderer output (R1)" do
      # Locks in the "no transformation between Renderer.render and
      # SafeString.new(...)" invariant. If a future change introduces
      # an extra post-process step inside to_html, this spec catches
      # the silent divergence.
      note = Note.create!(title: "r1-roundtrip")
      note.body = "para one\n\npara two"

      safe = note.body.to_html
      safe.should be_a(::Marten::Template::SafeString)
      safe.to_s.should eq ::MartenText::Renderer.render(note.body.content || "")
    end
  end
end
