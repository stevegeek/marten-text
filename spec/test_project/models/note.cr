# Host model — uses the shard's `has_markdown` macro to attach a
# markdown-bodied attribute backed by a NoteMarkdown row.
class Note < Marten::Model
  field :id, :big_int, primary_key: true, auto: true
  field :title, :string, max_size: 255, blank: false, null: false

  has_markdown :body, model: ::NoteMarkdown
end
