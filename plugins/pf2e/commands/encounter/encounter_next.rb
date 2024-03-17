module AresMUSH
  module Pf2e

    class PF2EncounterNextCmd
      include CommandHandler

      attr_accessor :encounter_id

      def parse_args
        self.encounter_id = integer_arg(cmd.args)
      end

      def handle

        # If they didn't specify the encounter ID, go get it.

        scene = enactor_room.scene

        encounter = self.encounter_id ?
          PF2Encounter[self.encounter_id] :
          PF2Encounter.get_encounter(enactor, scene)

        if !encounter
          client.emit_failure t('pf2e.bad_id', :type => 'encounter')
          return
        end

        # Verify that this character can modify the encounter.

        cannot_modify = Pf2e.can_modify_encounter(enactor, encounter)
        if cannot_modify
          client.emit_failure cannot_modify
          return
        end

        initlist = encounter.participants

        round = encounter.round
        this_init = encounter.next_init
        round_text = "Initiative advances!"
        next_init = (this_init + 1) % initlist.size

        new_round = this_init.zero?

        if new_round
          round = round + 1
          round_text = "%xh%xyNEW ROUND!%xn Round #{round}"
          encounter.update(round: round)
        end

        this_name = initlist[this_init][1]
        next_name = initlist[next_init][1]

        # Generate and send the message.

        @message = t('pf2e.advance_init',
          :current => this_name,
          :next => next_name,
          :init => initlist[this_init][0].to_i,
          :round => round_text
        )

        # Emit to the room.
        enactor_room.emit @message

        # Log message to the encounter.
        PF2Encounter.send_to_encounter(encounter, @message)

        # Log the message to the scene as an OOC message.
        Scenes.add_to_scene(scene, @message, Game.master.system_character, false, true)

        # If the current initiative is a PC, shoot them a global notifier.

        current_is_char = Character.named("#{this_name}")

        if current_is_char
          @init_msg = t('pf2e.your_init', :id => encounter.id)
          Global.notifier.notify_ooc(:char_init, @init_msg) do |c|
            c && c == current_is_char
          end
        end

        # Update the encounter object.

        encounter.update(next_init: next_init)

      end


    end
  end
end
