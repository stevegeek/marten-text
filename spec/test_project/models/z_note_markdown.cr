# Host-defined Markdown row model. Owns the polymorphic `to:` list
# (compile-time fixed in Marten), includes the shard's Renderable mixin
# to pick up `to_html` / `plain_text`.
class NoteMarkdown < Marten::Model
  include ::MartenMarkdown::Renderable

  field :id, :big_int, primary_key: true, auto: true
  field :record, :polymorphic, to: [Note, OtherNote], related: :markdowns
  field :name, :string, max_size: 64, blank: false, null: false
  field :content, :text, blank: true, null: false, default: ""
end
