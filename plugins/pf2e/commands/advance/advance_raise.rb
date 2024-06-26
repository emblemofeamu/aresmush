module AresMUSH
  module Pf2e

    class PF2AdvanceRaiseCmd
      include CommandHandler

      attr_accessor :type, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_equals_arg2)

        self.type = downcase_arg(args.arg1)
        self.value = upcase_arg(args.arg2)
      end

      def required_args
        [ self.type, self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle

        # Do they need to raise that this level?
        to_assign = enactor.pf2_to_assign
        key = "raise " + self.type

        exists = to_assign[key]

        unless exists
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        index = exists.index "open"

        # Do they have an open one to assign?
        unless index
          client.emit_failure t('pf2e.no_free', :element => 'ability boosts')
          return
        end

        advancement = enactor.pf2_advancement

        # Validate the value given.
        if self.type == 'ability'
          abilities = enactor.abilities
          object = abilities.select { |a| a.name_upcase == self.value }.first

          unless object
            client.emit_failure t('pf2e.bad_option',
            :element => 'ability',
            :options => abilities.map {|a| a.name}.join(", ")
            )
            return
          end

          ability = object.name

          # Did they already pick that one?
          if exists.include? ability
            client.emit_failure t('pf2e.boost_not_unique', :type => 'ability')
            return
          end

          exists.delete_at index
          exists << ability

          to_assign[key] = exists.sort
          advancement[key] = exists.sort

        elsif self.type == 'skill'
          skill_list = Global.read_config('pf2e_skills').keys
          skill_list_up = skill_list.map { |s| s.upcase }

          index = skill_list_up.index self.value

          unless index
            client.emit_failure t('pf2e.bad_skill', :name => titlecase_arg(self.value))
            return
          end

          item = skill_list[index]

          # Minimum level check for higher proficiencies.
          min_level = Pf2eSkills.min_level_for_prof(Pf2eSkills.get_next_prof(enactor, item))

          char_level = enactor.pf2_level + 1

          if char_level < min_level
            client.emit_failure t('pf2e.not_minimum_level', :level => min_level)
            return
          end

          to_assign[key] = item
          advancement[key] = item
        else
          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end



        # No sense in doing multiple individual writes.
        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save

        client.emit_success t('pf2e.adv_raise_selected', :name => item)

      end

    end
  end
end
