# marten_markdown

A Crystal shard for [Marten](https://martenframework.com) that ports
Rails Writebook's `has_markdown` / `MarkdownRenderer` stack — the
ActionText-Markdown analog — to Marten.

Rails Writebook patches ActionText to render Markdown via
`lib/rails_ext/action_text_markdown.rb`. Marten has no equivalent
framework hook, so this shard provides the same surface as a small,
self-contained package: a `has_markdown :body` macro on
`Marten::Model`, a configurable `MartenMarkdown::Renderer` pipeline
(CommonMark → tartrazine → image-wrap → heading-anchor), and a
`MartenMarkdown::Renderable` mixin for the host's concrete Markdown
row model.

## Installation

```yaml
dependencies:
  marten_markdown:
    github: stevegeek/marten-markdown
```

Then `shards install`.

## Usage

### 1. Define a concrete Markdown row model in your app

Marten's polymorphic `to:` list is compile-time fixed, so the shard
can't ship a usable polymorphic table — your app owns it:

```crystal
class Markdown < Marten::Model
  include MartenMarkdown::Renderable

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
MartenMarkdown.configure do |c|
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

## Why a shard?

Rails Writebook bolts Markdown rendering onto ActionText via a
monkey-patch (`lib/rails_ext/action_text_markdown.rb` and friends). The
Marten port keeps the same shape — `has_markdown` macro + polymorphic
storage row + render pipeline — but lives in its own shard because:

- Marten has no built-in rich-text equivalent to patch onto.
- The render pipeline is reusable across any Marten app that wants
  CommonMark → syntax-highlighted HTML.
- Keeping it separate lets the host model own the polymorphic `to:`
  list, which Marten requires at compile time.

## Development

```sh
shards install
script/cr spec/   # or `crystal spec`
```

## License

MIT — see `LICENSE`.
