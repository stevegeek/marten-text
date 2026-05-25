# marten_text

A Crystal shard for [Marten](https://martenframework.com) — the Marten
analog of Rails' [ActionText](https://guides.rubyonrails.org/action_text_overview.html)
framework feature.

Provides the same shape as ActionText (polymorphic content row with a
`has_*` macro on the host model, render pipeline + plain-text extraction)
with Markdown as the body format instead of Trix HTML. The pipeline runs
CommonMark via [`markd`](https://github.com/icyleaf/markd) and syntax
highlighting via [`tartrazine`](https://github.com/ralsina/tartrazine);
the two UI-facing pieces (image wrapping, heading anchors) are
configurable so the host app's CSS / Stimulus hooks stay in the host.

## Installation

```yaml
dependencies:
  marten_text:
    github: stevegeek/marten-text
```

Then `shards install`.

## Usage

### 1. Define a concrete Markdown row model in your app

Marten's polymorphic `to:` list is compile-time fixed, so the shard
can't ship a usable polymorphic table — your app owns it:

```crystal
class Markdown < Marten::Model
  include MartenText::Renderable

  field :id, :big_int, primary_key: true, auto: true
  field :record, :polymorphic, to: [Page, Section], related: :markdowns
  field :name, :string, max_size: 64
  field :content, :text, blank: true, null: false, default: "", max_size: 100_000
end
```

The `Renderable` mixin adds `to_html` and `plain_text` (rendered via the
configured pipeline).

**Cap `content` size.** SQLite and PostgreSQL `TEXT` columns are
effectively unbounded, and `to_html` re-runs the full markd +
tartrazine + image-wrap + heading-anchor pipeline on every call. A
malicious or careless author could store hundreds of megabytes of
markdown that then gets parsed on every page render. Pick a
`max_size:` that matches your editor's intent — `100_000` (≈100KB,
roughly 30 pages of prose) is a reasonable starting point for a
note-taking surface; pick lower for comment fields and higher for
long-form documents. Validation runs at the host's model layer
*before* the markdown row is saved, so an over-sized paste is
rejected at write time rather than blowing up at render time.

**Cache rendered HTML if your markdown is hot.** The render pipeline
is deterministic for a given `(content, configuration)` pair, but
re-running it per request adds up. If a row is read far more often
than it's written, cache the rendered HTML in a separate column /
fragment cache / CDN layer and invalidate on `body=`. The shard
deliberately does not bake this caching in (different hosts have
different cache layers, and freezing pre-rendered HTML in the DB
defeats configuration-driven changes like theme swaps and hook
rewrites).

### 2. Attach a markdown attribute to your model

```crystal
class Page < Marten::Model
  field :id, :big_int, primary_key: true, auto: true
  has_markdown :body, model: ::Markdown
end
```

`has_markdown :body` adds:

| Method      | Returns                                                 |
| ----------- | ------------------------------------------------------- |
| `page.body` | The `Markdown` row (autobuilt if absent, not persisted) |
| `page.body?`| `Bool` — true if a non-empty row exists                 |
| `page.body=`| Setter that saves the row immediately                   |

### 3. Configure the renderer hooks at boot

The renderer ships with sensible defaults but the two UI-facing pieces
— image wrapping and heading anchors — are configurable so your app's
CSS class names / Stimulus hooks live in your app, not in the shard:

**Security note for host-supplied wrappers.** `image_wrapper` receives the
raw URL from the markdown source. The default `markd_options` is `safe:
true`, which strips `javascript:`/`vbscript:`/non-image `data:` URLs from
`<img src=...>` *before* your hook sees them — but any wrapper that
re-interpolates `url` into an `<a href=...>` (or anywhere else) MUST
itself scheme-validate and HTML-escape `url`, otherwise a future flip to
`markd_options = Markd::Options.new(safe: false)` (e.g. for trusted-author
content) immediately makes `![cat](javascript:alert(1))` clickable.

The shard ships `MartenText::Configuration.safe_url?(url)` (allows
`http`, `https`, `mailto`, and relative URLs) and
`MartenText::Renderer.escape_html(s)` for exactly this purpose:

```crystal
MartenText.configure do |c|
  c.image_wrapper = ->(url : String, alt : String, title : String?) {
    # Refuse javascript:/vbscript:/data: etc. before interpolating.
    next %(<img alt="#{alt}">) unless MartenText::Configuration.safe_url?(url)

    safe_url = MartenText::Renderer.escape_html(url)
    %(<a data-action="lightbox#open:prevent" href="#{safe_url}">) +
    %(<img src="#{safe_url}" alt="#{alt}"></a>)
  }
  c.heading_anchor = ->(level : String, text : String, id : String) {
    %(<#{level} id="#{id}">#{text} ) +
    %(<a href="##{id}" class="heading__link" aria-hidden="true">#</a></#{level}>)
  }
end
```

You can also tweak `c.markd_options` and `c.syntax_theme` (any tartrazine theme name).

## Relationship to ActionText

| ActionText (Rails) | marten_text |
|---|---|
| `has_rich_text :body` | `has_markdown :body, model: ...` |
| `ActionText::RichText` model (HTML in `body` column) | host-defined polymorphic content row including `MartenText::Renderable` (markdown in `content` column) |
| Trix editor frontend | not bundled (host app picks an editor — e.g. `<house-md>`, `<trix-editor>`, plain `<textarea>`) |
| Embed/attachment expansion via SGID | not yet implemented |
| `to_plain_text` (HTML → text) | `plain_text` (markdown → text) |
| Sanitization on render | markd `safe: true` by default (raw HTML and `javascript:`/`vbscript:`/non-image `data:` URLs are stripped at parse time). Host-supplied `image_wrapper` hooks must scheme-validate and HTML-escape `url` if they re-interpolate it — see the configuration example above. |

The host owns the polymorphic content model because Marten's `field :polymorphic, to: [...]` list is fixed at compile time, so the shard can't ship a usable polymorphic table itself.

## Development

```sh
shards install
script/cr spec/   # or `crystal spec`
```

## License

MIT — see `LICENSE`.
