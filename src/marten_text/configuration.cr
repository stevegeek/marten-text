module MartenText
  # Render-time hooks. The renderer pipeline (CommonMark → tartrazine →
  # image-wrap → heading-anchor) is fixed; the *markup* emitted by the
  # image-wrap and heading-anchor passes is supplied by the host so the
  # shard doesn't bake in CSS class names or data-action hooks from any
  # particular UI.
  #
  # Configure once at app boot:
  #
  #   MartenText.configure do |c|
  #     c.image_wrapper = ->(url : String, alt : String, title : String?) {
  #       %(<a href="#{url}"><img src="#{url}" alt="#{alt}"></a>)
  #     }
  #     c.heading_anchor = ->(level : String, text : String, id : String) {
  #       %(<#{level} id="#{id}">#{text}</#{level}>)
  #     }
  #   end
  class Configuration
    # `(url, alt, title?) -> html_string`. Called once per top-level
    # `<img>` emitted by markd. Defaults to a vanilla `<img>` passthrough
    # so out-of-the-box renders are still valid HTML.
    property image_wrapper : Proc(String, String, String?, String) = ->default_image_wrapper(String, String, String?)

    # `(level, inner_text, id) -> html_string`. `level` is the tag name
    # (`"h1"` … `"h6"`); `inner_text` is the original heading inner HTML
    # (already rendered by markd); `id` is the deduplicated slug.
    property heading_anchor : Proc(String, String, String, String) = ->default_heading_anchor(String, String, String)

    # markd parser options. Override to tweak smart-punctuation, safe
    # mode, etc.
    property markd_options : Markd::Options = Markd::Options.new(smart: true, safe: false)

    # Tartrazine theme name (any theme from `Tartrazine.theme(...)`).
    property syntax_theme : String = "github"

    # Default markup helpers ---------------------------------------------

    # NOTE: `alt` and `title` arrive already HTML-escaped — markd emits
    # them that way and the renderer extracts them verbatim from the
    # post-markd HTML. Don't escape again here.
    private def self.default_image_wrapper(url : String, alt : String, title : String?) : String
      title_attr = (title && !title.empty?) ? %( title="#{title}") : ""
      %(<img src="#{url}" alt="#{alt}"#{title_attr}>)
    end

    private def self.default_heading_anchor(level : String, text : String, id : String) : String
      %(<#{level} id="#{id}">#{text}</#{level}>)
    end
  end

  # Module-level singleton config + DSL.
  @@configuration : Configuration = Configuration.new

  def self.configuration : Configuration
    @@configuration
  end

  def self.configure(&block : Configuration ->) : Nil
    block.call(@@configuration)
  end

  # Reset to defaults — convenient for specs.
  def self.reset_configuration! : Nil
    @@configuration = Configuration.new
  end
end
