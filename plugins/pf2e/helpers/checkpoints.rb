module AresMUSH
  module Pf2e

    # Rewinding a chargen stage.
    #
    # A checkpoint is one snapshot of the whole draft, taken as a stage begins. Restoring writes
    # back the values that have changed since - `DraftSnapshot.diff` over the two, which is the
    # mechanism `cg/undo` uses for a single command, over a longer stretch.
    #
    # Storing values rather than a list of keys is what makes it complete. A restore used to put
    # back five named attributes and rebuild the rest by re-running the stage's lock helpers, so
    # anything a lock helper did not rebuild was gone: the feat an Acolyte's background hands over,
    # the languages the player picked. It also needed a live client to re-run them with, which a
    # snapshot does not.
    module Checkpoints

      def self.rows(char)
        char.chargen_checkpoints.to_a
      end

      def self.find(char, name)
        rows(char).find { |row| row.name.to_s == name.to_s }
      end

      # Replaces any checkpoint of the same name, so a stage committed a second time is measured
      # from the second attempt. A name that is not a stage is not a checkpoint.
      def self.record!(char, name)
        return nil unless Chargen::Lifecycle.stage_at(name)

        find(char, name)&.delete

        Pf2eChargenCheckpoint.create(:character => char, :name => name.to_s,
                                     :shape => DraftSnapshot.of(char), :at => Time.now)
      end

      # Puts the character back to the shape the stage started in, and forgets the checkpoints
      # after it, which describe stages that have not happened now. The stage's own effects are not
      # replayed: everything the stages before it produced is in the snapshot already.
      def self.restore!(char, name)
        row = find(char, name)

        return nil unless row

        char = DraftSnapshot.restore!(char, DraftSnapshot.diff(row.shape, DraftSnapshot.of(char)))

        target = Chargen::Lifecycle.stage_at(name).to_i
        rows(char).each { |other| other.delete if Chargen::Lifecycle.stage_at(other.name).to_i > target }

        char
      end

      # The character's attributes as a stage began. `skill/unset` asks this to tell a skill
      # assigned during the skills stage from one a feat handed over after it.
      def self.attrs_at(char, name)
        (find(char, name)&.shape || {})['attrs'] || {}
      end

      def self.clear!(char)
        rows(char).each { |row| row.delete }
      end
    end
  end
end
