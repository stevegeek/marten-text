module MartenMarkdown
  # Mixin for the host's concrete Markdown row model. Provides:
  #   - `to_html` — render `content` through `MartenMarkdown::Renderer`.
  #   - `plain_text` — strip tags from the rendered HTML (suitable for
  #     full-text indexing).
  #
  # The host model must declare a `content : String` (or nilable
  # variant) field for these to compile. Typical shape:
  #
  #   class Books::Markdown < Marten::Model
  #     include MartenMarkdown::Renderable
  #
  #     field :id, :big_int, primary_key: true, auto: true
  #     field :record, :polymorphic, to: [Page, Section], related: :markdowns
  #     field :name, :string, max_size: 64
  #     field :content, :text, blank: true, null: false, default: ""
  #   end
  module Renderable
    def to_html : String
      ::MartenMarkdown::Renderer.render(content || "")
    end

    def plain_text : String
      rendered = to_html
      rendered.gsub(/<[^>]+>/, " ").gsub(/\s+/, " ").strip
    end
  end
end
