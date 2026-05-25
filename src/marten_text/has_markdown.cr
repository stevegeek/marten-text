module MartenText
end

# `has_markdown :body, model: ::Books::Markdown` on a Marten::Model
# declares a named markdown attribute stored in the host-defined
# polymorphic Markdown table.
#
# Adds the following methods to the host:
#   - `body` — fetch (or autobuild) the Markdown row for this attribute.
#     Returns the row instance; autobuilt rows are *not* saved until
#     `body=` is called.
#   - `body?` — Bool indicating whether the rendered body is non-blank
#     (mirrors ActionText's `RichText#blank?` semantics: whitespace,
#     `&nbsp;`, empty `<p></p>` all count as blank).
#   - `body=(content : String)` — set the markdown content. If the host
#     record is already persisted, saves immediately. If the host record
#     is unsaved, the assignment is buffered and flushed by an
#     `after_save` callback so it lands in the same DB transaction as
#     the host's INSERT — a rollback of the host's save also rolls back
#     the markdown insert (no orphan rows).
#   - `create_body!(content : String)` — fast-path single-INSERT helper
#     (skips the find-or-build SELECT). Same buffering behaviour as
#     `body=` when the host is unsaved.
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
#
# **Reserved instance variable names.** The macro emits two ivars per
# attribute on the host model. They are namespaced with the
# `@__marten_text_` prefix to minimise collision risk, but hosts MUST
# NOT define fields, methods, or other ivars that shadow these names:
#
#   - `@__marten_text_markdown_<name>` — per-instance cache of the
#     resolved (autobuilt-or-loaded) markdown row.
#   - `@__marten_text_pending_<name>` — pending markdown content
#     buffered by `body=`/`create_body!` until the host's `after_save`
#     callback flushes it.
#
# It also emits a private callback method
# `__marten_text_flush_pending_<name>` and registers it via
# `after_save` on the host.
#
# **`after_save` ordering.** The deferred-flush `after_save` callback
# is registered at the call site of `has_markdown`. Marten runs
# `after_save` callbacks in registration order. If your host model
# defines other `after_save` callbacks that need to **read the
# persisted markdown body** (e.g. push it to a search index, broadcast
# a notification with the rendered HTML, etc.), declare them *after*
# the `has_markdown` call. Callbacks declared *before* `has_markdown`
# will run while the body is still pending — `body.persisted?` is
# `false`, `body.content` reflects the in-memory pending value, and
# any FK lookup on `NoteMarkdown.filter(record_id: pk)` returns no
# rows. Concretely:
#
#   class Note < Marten::Model
#     field :id, :big_int, primary_key: true, auto: true
#     # ❌ runs BEFORE the flush — body is still pending
#     after_save :push_to_search_index_too_early
#
#     has_markdown :body, model: ::NoteMarkdown
#
#     # ✅ runs AFTER the flush — body row is persisted
#     after_save :push_to_search_index
#   end
#
# This is only relevant on the very first save of an unsaved host
# record (when the buffered-flush path activates); for subsequent
# `body=` updates on a persisted record the save happens inline and
# ordering is irrelevant.
class Marten::Model
  macro has_markdown(name, model)
    {% klass = @type %}

    @__marten_text_markdown_{{ name.id }} : ({{ model.id }})?
    @__marten_text_pending_{{ name.id }} : ::String? = nil

    after_save :__marten_text_flush_pending_{{ name.id }}

    def {{ name.id }} : {{ model.id }}
      cached = @__marten_text_markdown_{{ name.id }}
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
      @__marten_text_markdown_{{ name.id }} = result
      result
    end

    # Mirrors ActionText's `RichText#blank?`: returns true only if the
    # *rendered plain text* of the body is non-blank. Whitespace-only
    # content (`" "`, `"\n\n"`), structural-only markup (`"<p></p>"`),
    # and `&nbsp;` all return false — these all render to nothing the
    # user can perceive. Costs one markd render per call; cache at the
    # caller if hot.
    def {{ name.id }}? : ::Bool
      inst = {{ name.id }}
      !inst.plain_text.strip.empty?
    end

    def {{ name.id }}=(content : ::String) : ::Nil
      # Update the cached instance's content so subsequent reads in the
      # same fiber see the new value, regardless of whether we save now
      # or defer to after_save.
      m = {{ name.id }}
      m.content = content

      if persisted?
        # Host already exists in the DB — saving the markdown row now is
        # safe (no orphan risk) and matches the historical immediate
        # behaviour. Callers wanting transactional coupling with a host
        # update should wrap both in their own `Model.transaction`.
        m.save!
      else
        # Host is unsaved. Buffer the content; the after_save callback
        # flushes it inside the host's save transaction.
        @__marten_text_pending_{{ name.id }} = content
      end
    end

    # Build + save a fresh {{ name.id }} markdown row in a single INSERT,
    # skipping the find-or-build SELECT that `{{ name.id }}=` performs.
    # The caller's responsibility to use this only when the parent record
    # is known to have no existing markdown for this attribute (typical
    # on a just-created leafable). Mirrors ActiveRecord's
    # `create_<name>!` association method.
    #
    # If the cached `{{ name.id }}` accessor has already resolved to a
    # *persisted* row, raises `ArgumentError` — use `{{ name.id }}=` to
    # update an existing body. If the cached accessor holds an
    # autobuilt (unsaved) instance, that same instance is mutated and
    # saved, so any caller-held references stay valid.
    #
    # If the host record is unsaved at the time of the call, the
    # content is buffered exactly like `{{ name.id }}=` and flushed by
    # the after_save callback.
    def create_{{ name.id }}!(content : ::String) : ::Nil
      cached = @__marten_text_markdown_{{ name.id }}
      if cached && cached.persisted?
        raise ::ArgumentError.new(
          "create_{{ name.id }}!: a {{ name.id }} markdown row already exists for this record; use {{ name.id }}= to update it"
        )
      end

      m = cached || {{ model.id }}.new
      m.record = self
      m.name = {{ name.id.stringify }}
      m.content = content
      @__marten_text_markdown_{{ name.id }} = m

      if persisted?
        m.save!
      else
        @__marten_text_pending_{{ name.id }} = content
      end
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
      @__marten_text_markdown_{{ name.id }} = record || {{ model.id }}.new.tap do |new_md|
        new_md.record = self
        new_md.name = {{ name.id.stringify }}
        new_md.content = ""
      end
    end

    # Internal: `after_save` callback. Flushes any markdown content
    # buffered by `{{ name.id }}=` / `create_{{ name.id }}!` while the
    # host was unsaved. Runs inside the host's save transaction so a
    # later rollback (e.g. from a sibling `after_save` raising) also
    # rolls back this insert — no orphan markdown rows.
    private def __marten_text_flush_pending_{{ name.id }} : ::Nil
      pending = @__marten_text_pending_{{ name.id }}
      return if pending.nil?

      m = @__marten_text_markdown_{{ name.id }} || begin
        new_md = {{ model.id }}.new
        new_md.record = self
        new_md.name = {{ name.id.stringify }}
        @__marten_text_markdown_{{ name.id }} = new_md
        new_md
      end

      m.content = pending
      # The polymorphic `record` setter on the cached/autobuilt instance
      # was assigned before the host had a pk; reassign now that pk is
      # populated so the FK column gets the real value.
      m.record = self
      m.save!
      @__marten_text_pending_{{ name.id }} = nil
    end
  end
end
