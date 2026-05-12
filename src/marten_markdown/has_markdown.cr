module MartenMarkdown
end

# `has_markdown :body, model: ::Books::Markdown` on a Marten::Model
# declares a named markdown attribute stored in the host-defined
# polymorphic Markdown table.
#
# Adds three methods to the host:
#   - `body` — fetch (or autobuild) the Markdown row for this attribute.
#     Returns the row instance; autobuilt rows are *not* saved until
#     `body=` is called.
#   - `body?` — Bool indicating whether a non-empty body exists.
#   - `body=(content : String)` — set the markdown content (saves
#     immediately).
#
# The `model:` argument must be the concrete Marten::Model class the
# host defined for storing markdown rows — typically including
# `MartenMarkdown::Renderable` and declaring a polymorphic `record`
# field whose `to:` list includes the calling model.
#
# Why the macro accepts the model class instead of hardcoding one:
# Marten's polymorphic `to:` list must be known at compile time and
# the shard can't know which target types the host will use. The host
# owns the concrete table; this macro just emits the per-attribute
# accessors that read/write through it.
class Marten::Model
  macro has_markdown(name, model)
    {% klass = @type %}

    def {{ name.id }} : {{ model.id }}
      m = {{ model.id }}
        .filter(record_type: {{ klass.stringify }}, record_id: pk)
        .filter(name: {{ name.id.stringify }})
        .first
      if m
        m
      else
        {{ model.id }}.new.tap do |new_md|
          new_md.record = self
          new_md.name = {{ name.id.stringify }}
          new_md.content = ""
        end
      end
    end

    def {{ name.id }}? : ::Bool
      m = {{ model.id }}
        .filter(record_type: {{ klass.stringify }}, record_id: pk)
        .filter(name: {{ name.id.stringify }})
        .first
      !m.nil? && !m.content.try(&.empty?)
    end

    def {{ name.id }}=(content : ::String) : ::Nil
      m = {{ name.id }}
      m.content = content
      m.save!
    end
  end
end
