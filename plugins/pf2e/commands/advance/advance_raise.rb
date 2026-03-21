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

        exists = Array(exists)

        advancement = enactor.pf2_advancement

        # Validate the value given.
        if self.type == 'ability'
          abilities = enactor.abilities
          boosts_up = self.value.to_s.split(/\s+/).reject(&:empty?)

          if boosts_up.size != 4
            client.emit_failure t('pf2e.adv_ability_boost_count')
            return
          end

          if boosts_up.uniq.size != boosts_up.size
            client.emit_failure t('pf2e.adv_ability_boost_unique')
            return
          end

          ability_map = abilities.map { |a| [a.name_upcase, a.name] }.to_h
          ability_names = boosts_up.map { |boost| ability_map[boost] }

          unless ability_names.all?
            client.emit_failure t('pf2e.bad_option',
            :element => 'ability',
            :options => abilities.map {|a| a.name}.join(", ")
            )
            return
          end

          # Do they have an open one to assign?
          if exists.count("open") < 4
            client.emit_failure t('pf2e.no_free', :element => 'ability boosts')
            return
          end

          existing_selected = exists.reject { |value| value == "open" }
          existing_up = existing_selected.map { |value| value.to_s.upcase }

          if (existing_up & boosts_up).any?
            client.emit_failure t('pf2e.adv_ability_boost_unique')
            return
          end

          exists = (existing_selected + ability_names).sort
          item = ability_names.join(", ")

          to_assign[key] = exists
          advancement[key] = exists

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
        elsif self.type == 'skill choice'
          allowed_skills = Array(to_assign[key])
          allowed_skills_up = allowed_skills.map(&:upcase)

          index = allowed_skills_up.index self.value

          unless index
            client.emit_failure t('pf2e.bad_skill_choice', :options => allowed_skills.join(", "))
            return
          end

          item = allowed_skills[index]

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
