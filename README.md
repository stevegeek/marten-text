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
  field :content, :text, blank: true, null: false, default: ""
end
```

The `Renderable` mixin adds `to_html` and `plain_text` (rendered via the
configured pipeline).

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

```crystal
MartenText.configure do |c|
  c.image_wrapper = ->(url : String, alt : String, title : String?) {
    %(<a data-action="lightbox#open:prevent" href="#{url}">) +
    %(<img src="#{url}" alt="#{alt}"></a>)
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
| Sanitization on render | none (markdown is the source; rendering controls allowed HTML) |

The host owns the polymorphic content model because Marten's `field :polymorphic, to: [...]` list is fixed at compile time, so the shard can't ship a usable polymorphic table itself.

## Development

```sh
shards install
script/cr spec/   # or `crystal spec`
```

## License

MIT — see `LICENSE`.
