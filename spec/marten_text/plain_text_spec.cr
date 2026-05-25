require "../spec_helper"

# Regression specs for MED M3 (`Renderable#plain_text` operates on the
# markdown source, not the rendered HTML, so it avoids the `<[^>]+>`
# naïve-HTML-strip foot-gun and never leaks `<script>` / `<style>` body
# text). Direct unit tests of `Renderable.strip_markdown` cover the
# pure source-stripping behaviour; the instance-level `plain_text`
# tests confirm the wiring through a real persisted model.
describe MartenText::Renderable do
  describe ".strip_markdown" do
    # ---- the blank-detection contract that has_markdown's `body?`
    # depends on (Phase 3 M1). Each of these must round-trip through
    # `.strip.empty?` as true so `body?` correctly returns false.
    {
      "whitespace only"      => "   ",
      "multiple newlines"    => "\n\n",
      "empty <p></p>"        => "<p></p>",
      "&nbsp; entity"        => "&nbsp;",
      "heading with no text" => "# ",
      "link with empty text" => "[](https://x)",
    }.each do |description, source|
      it "returns blank for #{description}" do
        result = MartenText::Renderable.strip_markdown(source)
        result.strip.empty?.should be_true
      end
    end

    it "returns non-blank for genuine content" do
      result = MartenText::Renderable.strip_markdown("Hello **world**")
      result.strip.empty?.should be_false
      result.should contain "Hello"
      result.should contain "world"
      result.should_not contain "*"
    end

    it "preserves fenced code-block body text (drops fence markers + language label) (R4)" do
      # Phase 6 R4 — historically the whole fenced block was dropped,
      # which surprised users whose notes contained mostly code (a
      # code-only note reported `body? == false`). The fix preserves
      # the inner text and drops only the ``` markers and the optional
      # info-string / language label on the opening line.
      result = MartenText::Renderable.strip_markdown("Hi\n\n```ruby\nputs :secret\n```\n\nBye")
      result.should contain "Hi"
      result.should contain "Bye"
      result.should contain "puts"
      result.should contain "secret"
      # Fence markers and language label must be stripped.
      result.should_not contain "```"
      result.should_not contain "ruby"
    end

    it "preserves tilde fenced code-block body text (R4)" do
      result = MartenText::Renderable.strip_markdown("~~~python\nprint('hi')\n~~~")
      result.should contain "print"
      result.should contain "hi"
      result.should_not contain "~~~"
      result.should_not contain "python"
    end

    it "strips inline code markers but keeps the body" do
      result = MartenText::Renderable.strip_markdown("use `Array#map` to transform")
      result.should contain "Array#map"
      result.should_not contain "`"
    end

    it "extracts image alt text" do
      result = MartenText::Renderable.strip_markdown("see ![my cat](https://x/y.png)")
      result.should contain "my cat"
      result.should_not contain "https://"
      result.should_not contain "!"
    end

    it "extracts link text" do
      result = MartenText::Renderable.strip_markdown("see [the docs](https://x/y)")
      result.should contain "the docs"
      result.should_not contain "https://"
    end

    it "strips ATX headings while keeping the text" do
      result = MartenText::Renderable.strip_markdown("# Header One\n\n## Header Two\n\nbody")
      result.should contain "Header One"
      result.should contain "Header Two"
      result.should contain "body"
      result.should_not contain "#"
    end

    it "strips blockquote markers" do
      result = MartenText::Renderable.strip_markdown("> quoted line\n> second line")
      result.should contain "quoted line"
      result.should contain "second line"
      result.should_not contain ">"
    end

    it "strips list bullets (bulleted)" do
      result = MartenText::Renderable.strip_markdown("- one\n- two\n- three")
      result.should contain "one"
      result.should contain "two"
      result.should contain "three"
      result.should_not contain "-"
    end

    it "strips list bullets (ordered)" do
      result = MartenText::Renderable.strip_markdown("1. first\n2. second\n3. third")
      result.should contain "first"
      result.should contain "second"
      result.should_not contain "1."
      result.should_not contain "2."
    end

    it "strips raw HTML tags without leaking script body text" do
      # The whole reason for the M3 refactor: a naïve HTML-strip pass
      # on the rendered HTML would leak `alert(1)` here.
      result = MartenText::Renderable.strip_markdown("<script>alert(1)</script>")
      result.strip.empty?.should be_true
    end

    it "decodes HTML entities" do
      result = MartenText::Renderable.strip_markdown("AT&amp;T &lt;3 &#39;quoted&#39;")
      result.should contain "AT&T"
      result.should contain "<3"
      result.should contain "'quoted'"
    end

    it "collapses runs of whitespace" do
      result = MartenText::Renderable.strip_markdown("a  \n\n  b\t\tc")
      result.should eq "a b c"
    end
  end

  describe "Renderable#plain_text (instance-level wiring)" do
    it "extracts plain text from a persisted body" do
      note = Note.create!(title: "wired")
      note.body = "# Title\n\nSome **bold** body with `code`."

      pt = note.body.plain_text
      pt.should contain "Title"
      pt.should contain "Some"
      pt.should contain "bold"
      pt.should contain "body"
      pt.should contain "code"
      pt.should_not contain "#"
      pt.should_not contain "*"
      pt.should_not contain "`"
    end

    it "returns blank for whitespace-only content (preserves Phase 3 body? contract)" do
      note = Note.create!(title: "blank-via-plain-text")
      note.body = "   "
      note.body.plain_text.strip.empty?.should be_true
    end

    it "returns body? == true for a fenced-code-only note (R4)" do
      # Phase 6 R4 — a note that contains *only* a fenced code block
      # used to report `body? == false` because `strip_markdown`
      # dropped the entire block. After R4 the code text survives in
      # `plain_text`, so `body?` correctly reports true.
      note = Note.create!(title: "code-only")
      note.body = "```crystal\nputs :hello\n```"

      note.body.plain_text.should contain "puts"
      note.body.plain_text.should contain "hello"
      note.body?.should be_true
    end
  end
end
