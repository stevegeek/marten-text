require "../spec_helper"

# Regression spec for MED M4 (`Renderer#decode_entities` replaced with
# `HTML.unescape` from stdlib). The decoder runs on the captured body
# of a fenced `<pre><code>` block before handing the raw source to
# tartrazine; if it fails to decode an entity that markd emitted, the
# escaped form leaks into the highlighted output.
#
# The stdlib's `HTML.unescape` understands the full set of named
# entities plus numeric (`&#NN;` and `&#xHH;`) forms. The hand-rolled
# predecessor only knew `&lt; &gt; &quot; &#39; &amp;` (in that order)
# and silently passed through any entity outside that set — see
# review §M4.
#
# We exercise the round-trip end-to-end: each test feeds raw chars
# (`<`, `>`, `"`, `'`, `&`) inside a fenced code block, lets markd
# escape them however it sees fit, and asserts the rendered output
# contains the original chars (re-escaped by the fallback branch).
# A decoder regression would surface as `&amp;amp;`, `&amp;lt;`,
# `&amp;#39;`, etc. — i.e. double-escaping because the unescape step
# missed an entity.
describe MartenText::Renderer do
  describe "code-block entity decoding (M4)" do
    {
      "double-quote"             => %("hello"),
      "apostrophe"               => "it's",
      "less-than / greater-than" => "a < b > c",
      "ampersand"                => "AT&T",
      "all four mixed"           => %(if x < y && z > "0" then it's fine),
    }.each do |description, source_chars|
      it "round-trips #{description} through a fenced code block" do
        # `nosuchlang` triggers the fallback branch in
        # `highlight_or_passthrough`, which calls `escape_html(code)`
        # on the decoded source. We then check that the decoded form
        # was correctly recovered and re-escaped exactly once.
        html = MartenText::Renderer.render("```nosuchlang\n#{source_chars}\n```\n")

        # The classic double-escape signature — a decoder regression.
        # `&amp;XXX;` means the unescape step missed `&XXX;` and the
        # subsequent escape_html turned its leading `&` into `&amp;`.
        html.should_not contain "&amp;amp;"
        html.should_not contain "&amp;lt;"
        html.should_not contain "&amp;gt;"
        html.should_not contain "&amp;quot;"
        html.should_not contain "&amp;#39;"
        html.should_not contain "&amp;#x27;"
        html.should_not contain "&amp;apos;"
        html.should_not contain "&amp;#34;"

        # The output, once HTML-unescaped, should contain the original
        # source characters. (We don't lock in the *exact* escaped
        # form because that depends on markd's escape rules.)
        rendered_text = HTML.unescape(html.gsub(/<[^>]+>/, ""))
        rendered_text.should contain source_chars
      end
    end
  end
end
