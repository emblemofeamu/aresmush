module AresMUSH
  module Pf2e

    class PF2AdvanceArchetypeCmd
        include CommandHandler

    attr_accessor :type, :value

        def parse_args
            args = cmd.parse_args(ArgParser.arg1_equals_arg2)
      self.type = downcase_arg(args.arg1)
      self.value = downcase_arg(args.arg2)
        end

        def required_args
      [ self.type, self.value ]
        end

        def handle
            to_assign = enactor.pf2_to_assign
            
            # Get the archetype that was auto-assigned from the dedication feat.
            archetype = to_assign['archetype']
            
            unless archetype
              client.emit_failure "No archetype has been assigned."
              return
            end

            case self.type
            when 'specialty'
              unless to_assign['archetype_specialty']&.include?('open')
                client.emit_failure "You don't need to assign an archetype specialty."
                return
              end

              # Validate the specialty choice.
              valid_specialties = Global.read_config('pf2e_archetype_specialty', archetype)

              unless valid_specialties && valid_specialties.key?(self.value.capitalize)
                valid_list = valid_specialties&.keys&.sort&.join(", ") || "none"
                client.emit_failure t('pf2e.adv_invalid_archetype_specialty', :archetype => archetype, :options => valid_list)
                return
              end

              # Assign the specialty.
              to_assign['archetype_specialty'] = self.value.capitalize
              chosen_specialty = self.value.capitalize

              # Get the archetype info.
              archetype_info = enactor.pf2_archetypeinfo

              # Assign the archetype specialty to the slot matching the archetype slot.
              slot_index = nil
              if archetype == archetype_info["archetype1"]
                archetype_info["archetype_specialty1"] = chosen_specialty
                slot_index = 1
              elsif archetype == archetype_info["archetype2"]
                archetype_info["archetype_specialty2"] = chosen_specialty
                slot_index = 2
              elsif archetype == archetype_info["archetype3"]
                archetype_info["archetype_specialty3"] = chosen_specialty
                slot_index = 3
              elsif archetype == archetype_info["archetype4"]
                archetype_info["archetype_specialty4"] = chosen_specialty
                slot_index = 4
              end

              # Reassign the hashes so they can be saved.
              enactor.pf2_archetypeinfo = archetype_info
              enactor.pf2_to_assign = to_assign

              specialty_info = Global.read_config('pf2e_archetype_specialty', archetype, chosen_specialty) || {}
              specialty_features = specialty_info['initial_dedication'] || {}
              specialty_magic = specialty_features['magic_stats'] || {}
              specialty_choose = specialty_info['choose'] || {}
              specialty_choose_options = specialty_choose['options'] || {}

              if !specialty_magic.empty?
                base_class_key = enactor.pf2_base_info['charclass']
                assess_magic = PF2Magic.assess_magic_stats(enactor, specialty_magic)
                advancement = enactor.pf2_advancement || {}

                advancement['magic_stats'] ||= {}
                Pf2e.wrap_adv_magic_stats(advancement, base_class_key)
                existing_magic = advancement['magic_stats'][archetype] || {}
                advancement['magic_stats'][archetype] = existing_magic.merge(assess_magic['magic_stats'])

                magic_options = assess_magic['magic_options'] || {}
                if !magic_options.empty?
                  magic_options.each_pair do |k, v|
                    Pf2e.wrap_magic_assign(to_assign, k, base_class_key)
                    to_assign[k] ||= {}

                    existing = to_assign[k][archetype]
                    merged = if existing.is_a?(Hash) && v.is_a?(Hash)
                      existing.merge(v) { |_key, old_val, new_val| old_val.is_a?(Array) && new_val.is_a?(Array) ? (old_val + new_val) : new_val }
                    elsif existing.is_a?(Array) && v.is_a?(Array)
                      existing + v
                    else
                      v
                    end

                    to_assign[k][archetype] = merged
                  end
                end

                enactor.pf2_advancement = advancement
                enactor.pf2_to_assign = to_assign
              end

              if slot_index && specialty_choose_options.is_a?(Hash) && !specialty_choose_options.empty?
                to_assign['archetype specialty choice'] ||= {}
                to_assign['archetype specialty choice'][archetype] = {
                  'specialty' => chosen_specialty,
                  'choice' => 'open'
                }
                archetype_info["archetype_specialty_choice#{slot_index}"] = ""

                choose_name = specialty_choose['choice_name'] || "specialty choice"
                choose_options_list = specialty_choose_options.keys.sort.join(", ")
                client.emit_ooc t('pf2e.adv_archetype_specialty_choice_select', :archetype => archetype, :specialty => chosen_specialty, :choice => choose_name, :options => choose_options_list)

                enactor.pf2_archetypeinfo = archetype_info
                enactor.pf2_to_assign = to_assign
              end
              enactor.save

              client.emit_success t('pf2e.adv_archetype_specialty_assigned', :specialty => self.value.capitalize)
            when 'specialtychoice'
              choice_assignments = to_assign['archetype specialty choice'] || {}
              choice_entry = nil
              choice_archetype = archetype

              if choice_archetype && choice_assignments[choice_archetype]
                choice_entry = choice_assignments[choice_archetype]
              else
                choice_archetype = choice_assignments.keys.first
                choice_entry = choice_assignments[choice_archetype] if choice_archetype
              end

              unless choice_entry && choice_entry['choice'].to_s.downcase == 'open'
                client.emit_failure t('pf2e.adv_no_archetype_specialty_choice_needed')
                return
              end

              chosen_specialty = choice_entry['specialty']
              specialty_info = Global.read_config('pf2e_archetype_specialty', choice_archetype, chosen_specialty) || {}
              choose_info = specialty_info['choose'] || {}
              choose_options = choose_info['options'] || {}

              unless choose_options.is_a?(Hash) && !choose_options.empty?
                client.emit_failure t('pf2e.adv_no_archetype_specialty_choice_needed')
                return
              end

              matched_option = choose_options.keys.find { |opt| opt.to_s.casecmp?(self.value) }

              unless matched_option
                client.emit_failure t('pf2e.adv_invalid_archetype_specialty_choice', :options => choose_options.keys.sort.join(", "))
                return
              end

              choice_entry['choice'] = matched_option
              choice_assignments[choice_archetype] = choice_entry
              to_assign['archetype specialty choice'] = choice_assignments

              archetype_info = enactor.pf2_archetypeinfo || {}
              if choice_archetype == archetype_info["archetype1"]
                archetype_info["archetype_specialty_choice1"] = matched_option
              elsif choice_archetype == archetype_info["archetype2"]
                archetype_info["archetype_specialty_choice2"] = matched_option
              elsif choice_archetype == archetype_info["archetype3"]
                archetype_info["archetype_specialty_choice3"] = matched_option
              elsif choice_archetype == archetype_info["archetype4"]
                archetype_info["archetype_specialty_choice4"] = matched_option
              end

              option_info = choose_options[matched_option] || {}
              option_features = option_info['initial_dedication'] || {}
              option_magic = option_features['magic_stats'] || {}

              if !option_magic.empty?
                base_class_key = enactor.pf2_base_info['charclass']
                assess_magic = PF2Magic.assess_magic_stats(enactor, option_magic)
                advancement = enactor.pf2_advancement || {}

                advancement['magic_stats'] ||= {}
                Pf2e.wrap_adv_magic_stats(advancement, base_class_key)
                existing_magic = advancement['magic_stats'][choice_archetype] || {}
                advancement['magic_stats'][choice_archetype] = existing_magic.merge(assess_magic['magic_stats'])

                magic_options = assess_magic['magic_options'] || {}
                if !magic_options.empty?
                  magic_options.each_pair do |k, v|
                    Pf2e.wrap_magic_assign(to_assign, k, base_class_key)
                    to_assign[k] ||= {}

                    existing = to_assign[k][choice_archetype]
                    merged = if existing.is_a?(Hash) && v.is_a?(Hash)
                      existing.merge(v) { |_key, old_val, new_val| old_val.is_a?(Array) && new_val.is_a?(Array) ? (old_val + new_val) : new_val }
                    elsif existing.is_a?(Array) && v.is_a?(Array)
                      existing + v
                    else
                      v
                    end

                    to_assign[k][choice_archetype] = merged
                  end
                end

                enactor.pf2_advancement = advancement
              end

              enactor.pf2_archetypeinfo = archetype_info
              enactor.pf2_to_assign = to_assign
              enactor.save

              client.emit_success t('pf2e.adv_archetype_specialty_choice_assigned', :choice => matched_option, :specialty => chosen_specialty)
            when 'key ability'
              valid_abilities = Array(to_assign['archetype key ability'])

              if valid_abilities.empty?
                client.emit_failure t('pf2e.adv_no_archetype_key_ability_needed')
                return
              end

              chosen_ability = valid_abilities.find { |ability| ability.upcase == self.value.upcase }

              unless chosen_ability
                client.emit_failure t('pf2e.adv_invalid_archetype_key_ability', :archetype => archetype, :options => valid_abilities.join(", "))
                return
              end

              to_assign['archetype key ability'] = chosen_ability

              advancement = enactor.pf2_advancement || {}
              advancement['combat_stats'] ||= {}
              advancement['combat_stats']['archetype_class_dcs'] ||= {}
              advancement['combat_stats']['archetype_class_dcs'][archetype] ||= {}
              advancement['combat_stats']['archetype_class_dcs'][archetype]['key_abil'] = chosen_ability

              if !advancement['combat_stats']['archetype_class_dcs'][archetype]['prof']
                prof = Global.read_config('pf2e_archetype', archetype, 'initial_dedication', 'combat_stats', 'class_dc')
                advancement['combat_stats']['archetype_class_dcs'][archetype]['prof'] = prof if prof
              end

              enactor.pf2_advancement = advancement
              enactor.pf2_to_assign = to_assign
              enactor.save

              client.emit_success t('pf2e.adv_archetype_key_ability_assigned', :ability => chosen_ability, :archetype => archetype)
            when 'deity'
              unless to_assign['archetype deity']&.casecmp?('open')
                client.emit_failure t('pf2e.adv_no_archetype_deity_needed')
                return
              end

              deities = Global.read_config('pf2e_deities')&.keys || []
              chosen_deity = deities.find { |d| d.casecmp?(self.value) }

              unless chosen_deity
                client.emit_failure t('pf2e.adv_invalid_archetype_deity', :options => deities.sort.join(", "))
                return
              end

              if Global.read_config('pf2e', 'use_alignment')
                alignment = enactor.pf2_faith['alignment']

                if alignment.blank?
                  client.emit_failure t('pf2e.alignment_missing')
                  return
                end

                allowed_alignments = Global.read_config('pf2e_deities', chosen_deity, 'allowed_alignments') || []

                unless allowed_alignments.include?(alignment)
                  client.emit_failure t('pf2e.adv_archetype_deity_mismatch', :deity => chosen_deity, :alignment => alignment, :options => allowed_alignments.join(", "))
                  return
                end
              end

              to_assign['archetype deity'] = chosen_deity
              advancement = enactor.pf2_advancement || {}
              advancement['archetype_deity'] = chosen_deity

              divine_skill = Global.read_config('pf2e_deities', chosen_deity, 'divine_skill')
              if divine_skill && !divine_skill.to_s.strip.empty?
                pending_skills = Array(to_assign['raise skill'])
                pending_skills << divine_skill
                pending_skills = pending_skills.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
                to_assign['raise skill'] = pending_skills

                pending_adv_skills = Array(advancement['raise skill'])
                pending_adv_skills << divine_skill
                pending_adv_skills = pending_adv_skills.compact.map { |s| s.to_s.strip }.reject(&:empty?).uniq
                advancement['raise skill'] = pending_adv_skills

                client.emit_ooc t('pf2e.adv_archetype_deity_skill_assigned', :deity => chosen_deity, :skill => divine_skill)
              end

              enactor.pf2_advancement = advancement
              enactor.pf2_to_assign = to_assign
              enactor.save

              client.emit_success t('pf2e.adv_archetype_deity_assigned', :deity => chosen_deity, :archetype => archetype)
            else
              client.emit_failure t('pf2e.bad_option', :element => 'archetype assignment', :options => 'specialty, specialtychoice, key ability, deity')
              return
            end
        end

    end

  end
end
