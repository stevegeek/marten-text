module MartenText
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
# `MartenText::Renderable` and declaring a polymorphic `record`
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

    @__markdown_{{ name.id }} : ({{ model.id }})?

    def {{ name.id }} : {{ model.id }}
      cached = @__markdown_{{ name.id }}
      return cached if cached
      m = {{ model.id }}
        .filter(record_type: {{ klass.stringify }}, record_id: pk)
        .filter(name: {{ name.id.stringify }})
        .first
      result = m || {{ model.id }}.new.tap do |new_md|
        new_md.record = self
        new_md.name = {{ name.id.stringify }}
        new_md.content = ""
      end
      @__markdown_{{ name.id }} = result
      result
    end

    def {{ name.id }}? : ::Bool
      !{{ name.id }}.content.try(&.empty?)
    end

    def {{ name.id }}=(content : ::String) : ::Nil
      m = {{ name.id }}
      m.content = content
      m.save!
    end

    # Bulk-preload the {{ name.id }} markdown rows for an array of records,
    # warming each record's instance-level cache so subsequent calls to
    # `{{ name.id }}` don't hit the database. Mirrors ActiveRecord's
    # association preloader: one IN-clause SELECT covers the whole batch.
    #
    # Use this when rendering many records in a loop (e.g. a book's
    # leaves) to collapse N markdown queries into 1.
    def self.preload_{{ name.id }}(records : Enumerable({{ klass.id }})) : ::Nil
      pks = records.compact_map(&.pk).map(&.to_s)
      return if pks.empty?

      by_record_id = ::Hash(::String, {{ model.id }}).new(initial_capacity: pks.size)
      {{ model.id }}
        .filter(record_type: {{ klass.stringify }}, name: {{ name.id.stringify }})
        .filter(record_id__in: pks)
        .each { |m| by_record_id[m.record_id.to_s] = m }

      records.each do |r|
        pk = r.pk
        found = pk.nil? ? nil : by_record_id[pk.to_s]?
        r.__preload_markdown_{{ name.id }}(found)
      end
    end

    # Internal: assigns the per-instance cache slot. Public because the
    # class-level `preload_{{ name.id }}` helper above needs to reach
    # across instances; not part of the public API.
    def __preload_markdown_{{ name.id }}(record : {{ model.id }}?) : ::Nil
      @__markdown_{{ name.id }} = record || {{ model.id }}.new.tap do |new_md|
        new_md.record = self
        new_md.name = {{ name.id.stringify }}
        new_md.content = ""
      end
    end
  end
end
