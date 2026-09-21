module AresMUSH
  module Pf2e

    class PF2EncounterPrevCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = integer_arg(cmd.args)
      end

      def handle
        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene
        found = Pf2e::Encounters::Finder.find(enactor, scene, self.encounter_id)

        return if Pf2e::CharState.emit_error!(client, found)

        encounter = found.state

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
          return
        end

        initlist = encounter.participants
        moved = Pf2e::Encounters::Turn.move('prev', :size => initlist.size,
                                            :at => encounter.next_init, :round => encounter.round)

        return if Pf2e::CharState.emit_error!(client, moved)

        this_init = moved.state['current']
        next_init = moved.state['upcoming']

        encounter.update(:round => moved.state['round']) if moved.state['new_round']

        @message = t('pf2e.advance_init',
          :current => initlist[this_init][1],
          :next => initlist[next_init][1],
          :init => initlist[this_init][0].to_i,
          :round => t(moved.state['label'])
        )

        enactor_room.emit @message

        # Log to the encounter.
        PF2Encounter.send_to_encounter(encounter, @message)

        # Log the initiative message to the scene as an OOC message.
        Scenes.add_to_scene(encounter.scene, @message, Game.master.system_character, false, true)

        # If the current initiative is a PC, shoot them a global notifier.

        current_is_char = Character.named("#{this_name}")

        if current_is_char
          @init_msg = t('pf2e.your_init', :id => encounter.id)
          Global.notifier.notify_ooc(:char_init, @init_msg) do |c|
            c & c == current_is_char
          end
        end

        # Update the encounter object.

        encounter.update(next_init: next_init)

      end


    end
  end
end
