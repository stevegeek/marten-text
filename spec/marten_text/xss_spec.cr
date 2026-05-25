require "../spec_helper"

# Regression spec for CRIT H1 (configuration.cr: `safe: true` default).
#
# Locks in markd's safe-mode neutralisation of the classic XSS vectors
# enumerated in `reviews/marten-text-review.md` §H1. If any of these
# start passing through to the rendered output again (e.g. a future
# `safe: false` default flip, a markd regression), this spec breaks
# loudly.
describe MartenText::Renderer do
  describe "XSS hardening (markd safe: true default)" do
    # Single representative input per vector class. Each entry is the
    # markdown source; the assertions below check that the substrings
    # corresponding to *executable* HTML are absent from the rendered
    # output. We don't pin the exact rendered string because markd's
    # safe-mode placeholder for stripped content has changed across
    # versions ("<!-- raw HTML omitted -->" historically); the
    # invariant we care about is "nothing executable survives".
    {
      "raw <script> tag"      => %(<script>alert(1)</script>),
      "<img onerror> handler" => %(<img src=x onerror=alert(1)>),
      "javascript: link"      => %([click](javascript:alert(1))),
      "javascript: image"     => %(![evil](javascript:alert(1))),
      "iframe srcdoc"         => %(<iframe srcdoc="<script>alert(1)</script>"></iframe>),
      "svg onload"            => %(<svg onload=alert(1)></svg>),
      "raw <style>"           => %(<style>body{background:url("javascript:alert(1)")}</style>),
    }.each do |description, source|
      it "neutralises #{description}" do
        html = MartenText::Renderer.render(source)

        # No raw script execution surface.
        html.downcase.should_not contain "<script"
        html.downcase.should_not contain "onerror="
        html.downcase.should_not contain "onload="
        html.downcase.should_not contain "srcdoc="
        html.downcase.should_not contain "<style"

        # `javascript:` URLs must never reach the rendered HTML as an
        # attribute value. (The string can legitimately appear inside
        # markd's safe-mode placeholder comment as escaped text; this
        # check excludes that case by looking for the bare scheme.)
        html.should_not contain "javascript:alert"
      end
    end
  end
end
