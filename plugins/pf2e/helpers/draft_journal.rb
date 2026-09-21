module AresMUSH
  module Pf2e

    # A draft's steps, and taking the last one back.
    #
    # `step!` wraps whatever a command does to a drafting character, and records the difference it
    # made. Nothing about the step's meaning is recorded, only the values either side of it, so a
    # command that writes something new needs no entry here.
    #
    # Undo takes the last step, which is what makes it safe without revalidating anything: a step
    # cannot have dependents recorded before it, so putting back the values it changed can never
    # orphan an earlier pick. A player who took a class feat and then a skill feat that depends on
    # it undoes the skill feat first, which is both what a stack means and what they would expect.
    #
    # The journal is the draft's own history and stops at the commit boundary. Past it, the grant
    # ledger is the record and `admin/rollback` is the undo.
    module DraftJournal

      def self.rows(char)
        char.draft_steps.to_a.sort_by { |row| row.seq.to_i }
      end

      # The steps that are still in effect, oldest first.
      def self.steps(char)
        rows(char).select { |row| row.live? }
      end

      def self.undone(char)
        rows(char).reject { |row| row.live? }
      end

      def self.next_seq(char)
        rows(char).map { |row| row.seq.to_i }.max.to_i + 1
      end

      # Runs a command's work and records what it changed. Returns whatever the block returned, so
      # a caller can wrap a method body without changing what it answers.
      #
      # Records nothing for a step that changed nothing, which is how a refused command leaves no
      # trace, and nothing at all once the draft has closed.
      def self.step!(char, action)
        char = Character[char.id]

        return yield unless Ledger.drafting?(char)

        # The newest step kept the shape it left the character in, and that is the shape this step
        # starts from - so a step reads the character once rather than twice. A snapshot walks every
        # skill and ability row, which is most of what a draft command costs.
        previous = steps(char).last
        before = previous && !previous.shape_data.blank? ? previous.shape_data : DraftSnapshot.of(char)

        result = yield
        char = Character[char.id]
        after = DraftSnapshot.of(char)

        undo = DraftSnapshot.diff(before, after)

        return result if undo.empty?

        # A new step is a new branch: a redo after it would write over what was just done.
        undone(char).each { |row| row.delete }

        # Only the newest step needs the shape, so the one before it gives it up.
        previous&.update(:shape_data => {})

        Pf2eDraftStep.create(:character => char, :seq => next_seq(char), :action => action.to_s,
                             :undo => undo, :redo_to => DraftSnapshot.diff(after, before),
                             :shape => DraftSnapshot.digest(after), :shape_data => after,
                             :undone => false, :at => Time.now)

        result
      end

      # Has something changed the character since the last step was recorded?
      #
      # Each step stores a digest of the shape it left the character in. A change nothing recorded
      # leaves that digest describing a shape the character no longer has, and restoring an older
      # shape over it would take that change with it - so undo refuses, and the gap shows up as a
      # refusal rather than as a sheet quietly losing a pick.
      def self.stale?(char)
        last = rows(char).last

        return false unless last && !last.shape.blank?

        last.shape != DraftSnapshot.digest(DraftSnapshot.of(char))
      end

      # Takes the last step back and returns what it was, or nil when there is nothing to take back
      # or the journal is behind the character.
      def self.undo!(char)
        return nil if stale?(char)

        step = steps(char).last

        return nil unless step

        char = DraftSnapshot.restore!(char, step.undo)
        step.update(:undone => true)
        restamp(char)

        step.action
      end

      # Puts the most recently undone step back.
      def self.redo!(char)
        step = undone(char).sort_by { |row| row.seq.to_i }.first

        return nil unless step

        char = DraftSnapshot.restore!(char, step.redo_to)
        step.update(:undone => false)
        restamp(char)

        step.action
      end

      # Undo and redo move the character themselves, so the newest remaining step has to be told
      # what shape that left, or the next undo would see its own work as somebody else's.
      def self.restamp(char)
        last = rows(char).last

        return unless last

        shape = DraftSnapshot.of(Character[char.id])

        last.update(:shape => DraftSnapshot.digest(shape), :shape_data => shape)
      end

      def self.clear!(char)
        rows(char).each { |row| row.delete }
      end
    end
  end
end
