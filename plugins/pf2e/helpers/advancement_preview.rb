module AresMUSH
  module Pf2e

    # Named entry points for the questions Pf2e::DraftSheet answers, kept because several commands
    # and templates ask them by these names. The merging itself lives in DraftSheet, so there is one
    # implementation of "counting the picks made so far".

    def self.preview_repertoire(char, class_key = nil)
      DraftSheet.of(char).repertoire(class_key)
    end

    def self.preview_spellbook(char, class_key = nil)
      DraftSheet.of(char).spellbook(class_key)
    end

    def self.preview_skill_prof(char, skill_name)
      DraftSheet.of(char).skill_prof(skill_name)
    end

    def self.preview_max_spell_rank(char, charclass)
      DraftSheet.of(char).max_spell_rank(charclass)
    end

    def self.preview_feat_names(char)
      DraftSheet.of(char).feat_names
    end

    def self.preview_magic_tradition(char)
      DraftSheet.of(char).traditions
    end
  end
end
