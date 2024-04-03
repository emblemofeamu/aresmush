module AresMUSH
  module Pf2e

    class PF2InitModCmd
      include CommandHandler

      attr_accessor :encounter_id, :name, :init

      def parse_args
        if cmd.args
          args = trimmed_list_arg(cmd.args, "=")

          # If only two args are given, encounter_id is the nil.
          args.unshift(nil) unless args[2]

          self.encounter_id = args[0] ? integer_arg(args[0]) : nil
          self.name = downcase_arg(args[1])
          self.init = integer_arg(args[2])
        end
      end

      def required_args
        [ self.name, self.init ]
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

        index = initlist.index { |i| i[1].downcase.match? self.name }

        if !index
          client.emit_failure t('pf2e.not_found')
          return
        end

        # Fix goofy behavior where it was possible to modify the name by modding the init.

        name = initlist[index][1]

        PF2Encounter.remove_from_initiative(encounter, index)

        # If the character is not a PC, give them the adversary bonus.

        is_adversary = !(Character.find_one_by_name(name))

        PF2Encounter.add_to_initiative(encounter, name, self.init, is_adversary)

        client.emit_success t('pf2e.encounter_mod_ok',
          :name => initlist[index][1],
          :encounter => encounter.id,
          :init => self.init
        )

      end


    end
  end
end
