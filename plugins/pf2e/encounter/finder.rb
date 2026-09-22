module AresMUSH
  module Pf2e
    module Encounters

      # Which encounter a command is acting on.
      #
      # Six commands opened with the same lines: take the id if one was typed, otherwise find the one
      # in the room's scene, and refuse if there is none.
      #
      # Whether the character may change it stays in the shell, because `can_modify_encounter` renders
      # its own refusal and an Err carries a locale key rather than a sentence.
      module Finder

        def self.find(enactor, scene, id = nil)
          encounter = id ? PF2Encounter[id] : PF2Encounter.get_encounter(enactor, scene)

          return Err.new(:bad_id, 'pf2e.bad_id', 'type' => 'encounter') unless encounter

          Ok.new(:state => encounter)
        end
      end
    end
  end
end
