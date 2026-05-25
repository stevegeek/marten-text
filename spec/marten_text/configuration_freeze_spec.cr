require "../spec_helper"

# Regression spec for MED M6 (`MartenText.configuration` is process-wide
# mutable state; we don't refactor it in Phase 4, but we add an opt-in
# `frozen!` guard so hosts can lock the singleton after boot).
describe MartenText do
  describe ".frozen! / .configure / .reset_configuration!" do
    it "allows configure before frozen!" do
      MartenText.frozen?.should be_false
      MartenText.configure do |c|
        c.syntax_theme = "monokai"
      end
      MartenText.configuration.syntax_theme.should eq "monokai"
    end

    it "raises ConfigurationError on configure after frozen!" do
      MartenText.configure do |c|
        c.syntax_theme = "github"
      end
      MartenText.frozen!

      expect_raises(MartenText::ConfigurationError, /locked/) do
        MartenText.configure do |c|
          c.syntax_theme = "monokai"
        end
      end

      # The post-freeze attempt must not have leaked through.
      MartenText.configuration.syntax_theme.should eq "github"
    end

    it "raises ConfigurationError on reset_configuration! after frozen!" do
      MartenText.frozen!
      expect_raises(MartenText::ConfigurationError, /locked/) do
        MartenText.reset_configuration!
      end
    end

    it "reset_configuration!(_force: true) bypasses the freeze (test-helper path)" do
      MartenText.configure do |c|
        c.syntax_theme = "monokai"
      end
      MartenText.frozen!

      # The spec helper path: tests need to reset between examples
      # even after a previous example exercised `frozen!`.
      MartenText.reset_configuration!(_force: true)
      MartenText.frozen?.should be_false
      MartenText.configuration.syntax_theme.should eq "github" # default
    end

    it "frozen! is idempotent" do
      MartenText.frozen!
      MartenText.frozen!
      MartenText.frozen?.should be_true
    end
  end

  # Regression specs for post-fix re-review R3 — `MartenText.frozen!`
  # must also freeze the Configuration *instance* so direct setter
  # calls (`MartenText.configuration.syntax_theme = "monokai"`) raise
  # `ConfigurationError`. Before R3, only `configure` /
  # `reset_configuration!` were guarded; setter mutation slipped
  # through.
  describe "instance-level freeze (R3)" do
    it "freezes the Configuration instance when MartenText.frozen! is called" do
      MartenText.configuration.frozen?.should be_false
      MartenText.frozen!
      MartenText.configuration.frozen?.should be_true
    end

    {% for setter in %w(syntax_theme markd_options image_wrapper heading_anchor) %}
      it "raises ConfigurationError on direct .{{ setter.id }}= after frozen! (R3)" do
        MartenText.frozen!

        expect_raises(MartenText::ConfigurationError, /locked/) do
          {% if setter == "syntax_theme" %}
            MartenText.configuration.syntax_theme = "monokai"
          {% elsif setter == "markd_options" %}
            MartenText.configuration.markd_options = Markd::Options.new(smart: true, safe: false)
          {% elsif setter == "image_wrapper" %}
            MartenText.configuration.image_wrapper = ->(_u : String, _a : String, _t : String?) { "" }
          {% elsif setter == "heading_anchor" %}
            MartenText.configuration.heading_anchor = ->(_l : String, _t : String, _i : String) { "" }
          {% end %}
        end
      end
    {% end %}

    it "allows direct setters before frozen! (sanity)" do
      MartenText.configuration.syntax_theme = "monokai"
      MartenText.configuration.syntax_theme.should eq "monokai"
    end

    it "reset_configuration!(_force: true) un-freezes both the module flag and the instance" do
      MartenText.configure do |c|
        c.syntax_theme = "monokai"
      end
      MartenText.frozen!
      MartenText.configuration.frozen?.should be_true

      MartenText.reset_configuration!(_force: true)

      # Both flags must clear.
      MartenText.frozen?.should be_false
      MartenText.configuration.frozen?.should be_false

      # The post-reset Configuration is mutable again.
      MartenText.configuration.syntax_theme = "monokai"
      MartenText.configuration.syntax_theme.should eq "monokai"
    end

    it "the post-freeze direct mutation attempt did not leak through" do
      MartenText.configure do |c|
        c.syntax_theme = "github"
      end
      MartenText.frozen!

      expect_raises(MartenText::ConfigurationError) do
        MartenText.configuration.syntax_theme = "monokai"
      end

      # The frozen setter must have raised *before* assigning.
      MartenText.configuration.syntax_theme.should eq "github"
    end
  end
end
