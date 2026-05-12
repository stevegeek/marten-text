require "./spec_helper"

describe MartenText do
  describe "the has_markdown macro" do
    it "autobuilds a markdown row pointing at the host record when accessed unset" do
      note = Note.create!(title: "fresh")
      md = note.body
      md.should be_a(NoteMarkdown)
      md.record_type.should eq "Note"
      md.record_id.should eq note.pk
      md.name.should eq "body"
      md.content.should eq ""
      # Autobuilt; not yet persisted.
      md.persisted?.should be_false
    end

    it "persists a markdown row when body= is called" do
      note = Note.create!(title: "writeable")
      note.body = "# hello"

      stored = NoteMarkdown.filter(record_type: "Note", record_id: note.pk, name: "body").first
      stored.should_not be_nil
      stored.not_nil!.content.should eq "# hello"
    end

    it "subsequent body reads return the persisted row" do
      note = Note.create!(title: "rw")
      note.body = "first"
      note.body = "second"

      note.body.content.should eq "second"
      NoteMarkdown.filter(record_type: "Note", record_id: note.pk).count.should eq 1
    end

    it "body? returns false when no row exists" do
      note = Note.create!(title: "empty")
      note.body?.should be_false
    end

    it "body? returns false when the row exists but content is empty" do
      note = Note.create!(title: "blank")
      note.body = ""
      note.body?.should be_false
    end

    it "body? returns true when content is non-empty" do
      note = Note.create!(title: "full")
      note.body = "anything"
      note.body?.should be_true
    end
  end

  describe MartenText::Renderable do
    it "to_html renders markdown through the renderer pipeline" do
      note = Note.create!(title: "render me")
      note.body = "# hi"
      note.body.to_html.should contain "<h1"
      note.body.to_html.should contain "hi"
    end

    it "plain_text strips HTML tags" do
      note = Note.create!(title: "strip")
      note.body = "# hi\n\nbody **text**"
      pt = note.body.plain_text
      pt.should_not contain "<"
      pt.should contain "hi"
      pt.should contain "text"
    end
  end

  describe MartenText::Renderer do
    it "calls the configured image_wrapper for top-level images" do
      seen = [] of {String, String, String?}
      MartenText.configure do |c|
        c.image_wrapper = ->(url : String, alt : String, title : String?) {
          seen << {url, alt, title}
          %(<figure data-test="wrapped"><img src="#{url}" alt="#{alt}"></figure>)
        }
      end

      html = MartenText::Renderer.render(%(![cat](https://x/y.png "kitten")))
      seen.size.should eq 1
      seen[0][0].should eq "https://x/y.png"
      seen[0][1].should eq "cat"
      seen[0][2].should eq "kitten"
      html.should contain %(data-test="wrapped")
    end

    it "calls the configured heading_anchor for every heading and dedupes ids" do
      seen = [] of {String, String, String}
      MartenText.configure do |c|
        c.heading_anchor = ->(level : String, text : String, id : String) {
          seen << {level, text, id}
          %(<#{level} data-id="#{id}">#{text}</#{level}>)
        }
      end

      html = MartenText::Renderer.render("# alpha\n\n## beta\n\n## beta\n")
      seen.size.should eq 3
      seen[0][0].should eq "h1"
      seen[0][2].should eq "alpha"
      seen[1][2].should eq "beta"
      seen[2][2].should eq "beta-2"
      html.should contain %(<h1 data-id="alpha">)
      html.should contain %(<h2 data-id="beta-2">)
    end

    it "default image hook emits a passthrough <img>" do
      html = MartenText::Renderer.render(%(![cat](/u.png)))
      html.should contain %(<img src="/u.png" alt="cat">)
    end

    it "default heading hook emits a plain heading with an id" do
      html = MartenText::Renderer.render("# Hello World")
      html.should contain %(<h1 id="hello-world">Hello World</h1>)
    end

    it "highlights fenced code via tartrazine when a known language is set" do
      html = MartenText::Renderer.render("```ruby\nputs :hi\n```\n")
      # Tartrazine emits highlighting spans with classes; we don't care
      # about specific tokens, just that something richer than the raw
      # <pre><code> got produced.
      html.should contain "<pre"
      html.should_not eq Markd.to_html("```ruby\nputs :hi\n```\n")
    end

    it "falls back to a bare <pre><code> for unknown languages" do
      html = MartenText::Renderer.render("```nosuchlang\nfoo\n```\n")
      html.should contain "<pre><code"
      html.should contain "foo"
    end
  end
end
