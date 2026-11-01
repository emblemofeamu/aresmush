module AresMUSH
  module Pf2e
    module Encounters

      # An encounter ending, however it ends: its GM ending it, or its scene stopping.
      #
      # Whatever could not outlast the fight ends with it; so do the turn's counts, what may be used once
      # an encounter, a trust given for this fight, and the cover and concealment set on its combatants.
      # What its characters used of their consumables comes off their own inventories, and what it gave
      # them goes on (`Equipment.settle!`). Its history is frozen from here. Answers what ended, and what
      # could not be settled, as events for whoever tells it.
      module Ending
        def self.end!(encounter)
          PF2Encounter[encounter.id].update(:is_active => false)

          ended = ActiveEffects.encounter_ended(encounter)

          Turns.holders(PF2Encounter[encounter.id]).each do |holder|
            TurnState.reset(holder, 'encounter')
            TurnState.write(holder, 'turn' => {})
          end

          PF2Encounter[encounter.id].update(:trusted => [], :cover => {}, :concealment => {})

          ended + PF2Encounter[encounter.id].states.to_a.flat_map { |state| Equipment.settle!(state) }
        end

        # A scene stopping ends whatever encounter is still running in it, and tells the scene so.
        def self.scene_stopping(scene)
          PF2Encounter.running(:scene_id => scene.id).to_a.each do |encounter|
            end!(encounter)
            tell_ended(PF2Encounter[encounter.id], t('pf2e.encounter_ended_with_scene', :id => encounter.id), :with_scene => true)
          end
        end

        # Tells everyone the encounter has ended: the game client a banner between the lines its start
        # banner has, a page the notice's details to lay out as its own.
        def self.tell_ended(encounter, said, room: nil, with_scene: false)
          # As text whatever it was found by: Ohm keeps the id an object was looked up with.
          details = { 'id' => encounter.id.to_s, 'with_scene' => with_scene || nil }.compact

          Announce.tell(encounter, banner(said), :room => room, :notice => 'end', :notice_details => details)
        end

        def self.banner(said)
          "%lh%r#{SubstitutionFormatter.center("#{Global.read_config('pf2e', 'title_color')}#{said}%xn", 78)}%r%lf"
        end
      end
    end
  end
end
