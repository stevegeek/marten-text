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
    # Per-instance freeze flag. Set by `freeze!`; once set, every
    # setter on this configuration raises `ConfigurationError`. The
    # module-level `MartenText.frozen!` guards `configure` and
    # `reset_configuration!`; this instance-level flag closes the
    # remaining mutation path through direct setter calls like
    # `MartenText.configuration.syntax_theme = "monokai"`. The two
    # work together — `MartenText.frozen!` flips both — but the
    # instance flag is what actually stops setter mutation.
    @frozen : Bool = false

    # `(url, alt, title?) -> html_string`. Called once per top-level
    # `<img>` emitted by markd. Defaults to a vanilla `<img>` passthrough
    # so out-of-the-box renders are still valid HTML.
    getter image_wrapper : Proc(String, String, String?, String) = ->default_image_wrapper(String, String, String?)

    def image_wrapper=(value : Proc(String, String, String?, String)) : Proc(String, String, String?, String)
      check_frozen!(:image_wrapper)
      @image_wrapper = value
    end

    # `(level, inner_text, id) -> html_string`. `level` is the tag name
    # (`"h1"` … `"h6"`); `inner_text` is the original heading inner HTML
    # (already rendered by markd); `id` is the deduplicated slug.
    getter heading_anchor : Proc(String, String, String, String) = ->default_heading_anchor(String, String, String)

    def heading_anchor=(value : Proc(String, String, String, String)) : Proc(String, String, String, String)
      check_frozen!(:heading_anchor)
      @heading_anchor = value
    end

    # markd parser options. Defaults to `safe: true` so raw HTML blocks
    # / inlines and dangerous URL schemes (`javascript:`, `vbscript:`,
    # non-image `data:`) are stripped at the markd layer. Hosts that
    # render trusted-author content can opt in to `safe: false`, but
    # they then own sanitisation themselves (see the README and
    # `Renderable#to_html`).
    getter markd_options : Markd::Options = Markd::Options.new(smart: true, safe: true)

    def markd_options=(value : Markd::Options) : Markd::Options
      check_frozen!(:markd_options)
      @markd_options = value
    end

    # Tartrazine theme name (any theme from `Tartrazine.theme(...)`).
    getter syntax_theme : String = "github"

    def syntax_theme=(value : String) : String
      check_frozen!(:syntax_theme)
      @syntax_theme = value
    end

    # Returns `true` if `freeze!` has been called on this Configuration
    # instance. Setter calls on a frozen instance raise
    # `ConfigurationError`.
    def frozen? : Bool
      @frozen
    end

    # Locks this Configuration instance against further mutation: every
    # subsequent setter call raises `ConfigurationError`. Called by
    # `MartenText.frozen!`; hosts normally use that module-level entry
    # point. Idempotent.
    def freeze! : Nil
      @frozen = true
    end

    # Internal: re-enables mutation. Used by `MartenText.reset_configuration!`
    # so the post-reset Configuration starts unfrozen even when a
    # previous example exercised the freeze contract. Not part of the
    # public API; production code must not call this.
    protected def unfreeze! : Nil
      @frozen = false
    end

    private def check_frozen!(name : Symbol) : Nil
      return unless @frozen
      raise ConfigurationError.new(
        "MartenText.configuration.#{name}= called after freeze!; configuration is locked"
      )
    end

    # Default markup helpers ---------------------------------------------

    # Schemes safe to render as an image / link `src` / `href`. `nil`
    # covers relative URLs (e.g. `/uploads/foo.png`, `./bar.gif`) which
    # `URI.parse` parses with a nil scheme.
    SAFE_URL_SCHEMES = {"http", "https", "mailto"}

    # `data:` URLs are allowed *only* for inline images whose media type
    # is one of these. Matches markd's own allow-pattern
    # (`/^data:image\/(?:png|gif|jpeg|webp)/i` in
    # `lib/markd/src/markd/rule.cr`) so the default image_wrapper
    # doesn't reject inputs markd has already let through. Everything
    # else under `data:` (notably `data:text/html,...`, which is an XSS
    # vector) is rejected.
    SAFE_DATA_IMAGE_RE = /\Adata:image\/(?:png|gif|jpeg|webp)[;,]/i

    # Returns `true` if `url` parses to a relative URL, one of the
    # `SAFE_URL_SCHEMES`, or a `data:image/(png|gif|jpeg|webp)…` URL.
    # Used by `default_image_wrapper` to refuse `javascript:`,
    # `vbscript:`, non-image `data:`, etc. before interpolation.
    # Defense in depth: with `markd_options.safe = true` (the default)
    # markd already strips dangerous schemes from `<img src=...>`, but
    # any host hook that interpolates `url` MUST do the same — see
    # the README for the recommended recipe.
    def self.safe_url?(url : String) : Bool
      return true if url.matches?(SAFE_DATA_IMAGE_RE)
      scheme = URI.parse(url).scheme
      scheme.nil? || SAFE_URL_SCHEMES.includes?(scheme)
    rescue URI::Error
      false
    end

    # NOTE: `alt` and `title` arrive already HTML-escaped — markd emits
    # them that way and the renderer extracts them verbatim from the
    # post-markd HTML. `url` is markd-URL-encoded but NOT HTML-escaped
    # and NOT scheme-validated, so this helper does both before
    # interpolating. Unsafe schemes degrade to a plain `<img alt="…">`
    # with no `src` (renders as the alt-text fallback in browsers).
    private def self.default_image_wrapper(url : String, alt : String, title : String?) : String
      return %(<img alt="#{alt}">) unless safe_url?(url)

      safe_url = MartenText::Renderer.escape_html(url)
      title_attr = (title && !title.empty?) ? %( title="#{title}") : ""
      %(<img src="#{safe_url}" alt="#{alt}"#{title_attr}>)
    end

    private def self.default_heading_anchor(level : String, text : String, id : String) : String
      %(<#{level} id="#{id}">#{text}</#{level}>)
    end
  end

  # Raised when `MartenText.configure` or `MartenText.reset_configuration!`
  # is called after `MartenText.frozen!` has been invoked. The freeze
  # opt-in is the host's way of asserting "all configuration is done; any
  # subsequent mutation is a bug." See `MartenText.frozen!` for the full
  # rationale.
  class ConfigurationError < ::Exception
  end

  # Module-level singleton config + DSL.
  @@configuration : Configuration = Configuration.new
  @@frozen : Bool = false

  # Returns the process-wide configuration singleton.
  #
  # **Boot-only mutation.** This object is shared across every fiber in
  # the process. Mutating it after the first request races concurrent
  # readers: a fiber rendering a `MartenText::Renderer` call midway
  # through a hook swap will see a half-applied configuration. Set
  # everything once in your `config/initializers/marten_text.cr` (or
  # equivalent boot file) and never touch the singleton again at
  # runtime. To enforce this at runtime, opt in to `MartenText.frozen!`
  # after boot.
  def self.configuration : Configuration
    @@configuration
  end

  # Yields the configuration singleton for mutation.
  #
  # **Boot-only.** Configuration is a process-wide singleton; mutating
  # it after the first request races concurrent fibers. Call
  # `MartenText.configure` exactly once at app boot (from
  # `config/initializers/marten_text.cr` or equivalent) and never
  # again at runtime.
  #
  # Hosts that want runtime enforcement should call `MartenText.frozen!`
  # after the boot-time configure block; subsequent calls then raise
  # `MartenText::ConfigurationError`.
  def self.configure(&block : Configuration ->) : Nil
    raise ConfigurationError.new(
      "MartenText.configure called after MartenText.frozen!; configuration is locked"
    ) if @@frozen
    block.call(@@configuration)
  end

  # Reset to defaults. **Production code must not call this** — it
  # races concurrent readers exactly like `configure`. Provided for
  # spec isolation; specs that pre-freeze the config must pass
  # `_force: true` to bypass both the module-level freeze guard AND
  # the per-instance freeze flag on the current Configuration. See
  # `spec/spec_helper.cr` for the usage pattern.
  def self.reset_configuration!(*, _force : Bool = false) : Nil
    raise ConfigurationError.new(
      "MartenText.reset_configuration! called after MartenText.frozen!; configuration is locked. " \
      "Pass _force: true to override (test helpers only)."
    ) if @@frozen && !_force
    @@configuration = Configuration.new
    @@frozen = false if _force
  end

  # Opt-in runtime guard against post-boot configuration mutation.
  #
  # Call this after your boot-time `MartenText.configure` block to lock
  # the singleton **and** the current Configuration instance: subsequent
  # `MartenText.configure` / `MartenText.reset_configuration!` calls
  # raise `MartenText::ConfigurationError`, and so do direct setter
  # calls like `MartenText.configuration.syntax_theme = "monokai"`.
  # Idempotent — calling `frozen!` more than once is a no-op.
  #
  # This is a defence-in-depth measure; the real fix for per-tenant /
  # per-request configuration is to thread a config object through
  # `Renderer.render` (tracked as a follow-up, not in scope for the
  # current phase).
  def self.frozen! : Nil
    @@frozen = true
    @@configuration.freeze!
  end

  # Returns `true` if `MartenText.frozen!` has been called and the
  # configuration singleton is locked against mutation.
  def self.frozen? : Bool
    @@frozen
  end
end
