require "../spec_helper"

# Regression specs for marten-text-review.md §M1, §M2, §M7 (Phase 3).
#
# §M1 — `body?` mirrors ActionText `RichText#blank?`: whitespace-only,
#       `&nbsp;`, and empty-structural-markup content count as blank.
# §M2 — `create_body!` coordinates with the autobuild cache; raises if
#       a persisted body already exists; mutates the cached unsaved
#       instance otherwise (callers' references stay valid).
# §M7 — `body=` set on an unsaved host record is buffered and flushed
#       inside the host's save transaction, so a rollback of the host's
#       INSERT also rolls back the markdown INSERT.
describe MartenText do
  describe "body? (blank-aware)" do
    {
      "whitespace only"             => " ",
      "multiple newlines"           => "\n\n",
      "empty <p></p>"               => "<p></p>",
      "non-breaking space (&nbsp;)" => "&nbsp;",
    }.each do |description, content|
      it "returns false for #{description}" do
        note = Note.create!(title: "blank-#{description.gsub(' ', '-')}")
        note.body = content
        note.body?.should be_false
      end
    end

    it "returns true for genuine content (smoke)" do
      note = Note.create!(title: "real")
      note.body = "# hello world"
      note.body?.should be_true
    end
  end

  describe "create_body! cache coordination (M2)" do
    it "raises ArgumentError when a persisted body already exists" do
      note = Note.create!(title: "double-create")
      note.body = "first"
      note.body.persisted?.should be_true

      expect_raises(ArgumentError, /already exists/) do
        note.create_body!("second")
      end
    end

    it "mutates the autobuilt cached instance in place (callers' references stay valid)" do
      note = Note.create!(title: "autobuild-then-create")

      # Trigger the autobuild — `cached` is an unsaved row in the ivar
      # cache. A caller holding this reference expects it to reflect
      # the post-create_body! state.
      cached_before = note.body
      cached_before.persisted?.should be_false
      cached_before_object_id = cached_before.object_id

      note.create_body!("real body")

      # Same Crystal object — not a freshly-allocated row.
      note.body.object_id.should eq cached_before_object_id
      cached_before.content.should eq "real body"
      cached_before.persisted?.should be_true
    end

    it "still works when no cache has been warmed (fresh path)" do
      note = Note.create!(title: "fresh-create-body")
      note.create_body!("hello")
      note.body.content.should eq "hello"
      note.body.persisted?.should be_true
    end
  end

  describe "transactional safety (M7)" do
    it "rolls back the markdown row when the host's transaction rolls back" do
      # Snapshot the count so we don't depend on test ordering.
      before_count = NoteMarkdown.filter(name: "body").count

      # Use Marten's manual-rollback idiom: raise Errors::Rollback inside
      # the block to abort the transaction without re-raising.
      Note.transaction do
        note = Note.new(title: "rollback-host")
        note.body = "this should not survive"
        note.save!
        # Now bail out of the transaction.
        raise Marten::DB::Errors::Rollback.new("intentional")
      end

      after_count = NoteMarkdown.filter(name: "body").count
      after_count.should eq before_count
    end

    it "buffers body= on an unsaved host and flushes it via after_save" do
      note = Note.new(title: "unsaved-then-save")
      note.body = "buffered content"

      # Nothing persisted yet — host hasn't been saved.
      note.persisted?.should be_false
      NoteMarkdown.filter(record_type: "Note", name: "body").filter(content: "buffered content").exists?.should be_false

      # In-memory read should still reflect the pending value.
      note.body.content.should eq "buffered content"

      note.save!

      stored = NoteMarkdown.filter(record_type: "Note", record_id: note.pk, name: "body").first
      stored.should_not be_nil
      stored.not_nil!.content.should eq "buffered content"
    end

    it "buffers create_body! on an unsaved host and flushes it via after_save" do
      note = Note.new(title: "unsaved-create-body")
      note.create_body!("via create_body!")

      note.persisted?.should be_false
      note.body.content.should eq "via create_body!"

      note.save!

      stored = NoteMarkdown.filter(record_type: "Note", record_id: note.pk, name: "body").first
      stored.should_not be_nil
      stored.not_nil!.content.should eq "via create_body!"
    end
  end
end
