module AresMUSH
  module Pf2e

    class PF2AdvanceResetCmd
      include CommandHandler

      # This command has no args and simply clears all the advancement stuff they've done.

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        advancement = enactor.pf2_advancement

        # Remove a spell swap done during this advancement.
        if advancement['repertoire_swap']
          swap = advancement['repertoire_swap']
          magic = enactor.magic
          charclass = enactor.pf2_base_info['charclass']

          if magic && charclass
            level = swap['level']
            old_spell = swap['old']
            new_spell = swap['new']

            repertoire = magic.repertoire || {}
            class_rep = repertoire[charclass] || {}
            level_list = Array(class_rep[level])

            index = level_list.index { |s| s.to_s.casecmp?(new_spell.to_s) }
            if index
              level_list[index] = old_spell
              class_rep[level] = level_list
              repertoire[charclass] = class_rep
              magic.update(repertoire: repertoire)
            end
          end
        end

        # Remove an archetype added during this advancement.
        if advancement['feats']
          advancement['feats'].each do |feat_type, feat_list|
            feat_list.each do |feat_name|
              feat_details = Pf2e.get_feat_details(feat_name)
              if feat_details && !feat_details.is_a?(String)
                fdetails = feat_details[1]
                if fdetails && fdetails['feat_type']&.include?('Dedication')
                  archetype_slot = enactor.pf2_archetypeinfo || {}
                  assoc_archetypes = fdetails['assoc_archetype']
                  to_assign = enactor.pf2_to_assign
                  if assoc_archetypes && !assoc_archetypes.empty?
                    archetype = assoc_archetypes.first
                    # Remove the archetype from the last slot it was added to
                    if archetype_slot['archetype4'] == archetype
                      archetype_slot['archetype4'] = ""
                    elsif archetype_slot['archetype3'] == archetype
                      archetype_slot['archetype3'] = ""
                    elsif archetype_slot['archetype2'] == archetype
                      archetype_slot['archetype2'] = ""
                    elsif archetype_slot['archetype1'] == archetype
                      archetype_slot['archetype1'] = ""
                    end
                    enactor.pf2_archetypeinfo = archetype_slot
                  end
                  if to_assign['archetype_specialty'] && !to_assign['archetype_specialty'].empty?
                    # If the archetype has a specialty, remove it as well.
                    archetype_specialty_slot = enactor.pf2_archetypeinfo || {}
                    archetype_specialty = to_assign['archetype_specialty']
                    if archetype_specialty_slot['archetype_specialty4'] == archetype_specialty
                      archetype_specialty_slot['archetype_specialty4'] = ""
                    elsif archetype_specialty_slot['archetype_specialty3'] == archetype_specialty
                      archetype_specialty_slot['archetype_specialty3'] = ""
                    elsif archetype_specialty_slot['archetype_specialty2'] == archetype_specialty
                      archetype_specialty_slot['archetype_specialty2'] = ""
                    elsif archetype_specialty_slot['archetype_specialty1'] == archetype_specialty
                      archetype_specialty_slot['archetype_specialty1'] = ""
                    end
                    enactor.pf2_archetypeinfo = archetype_specialty_slot
                  end
                  if to_assign['archetype specialty choice'].is_a?(Hash)
                    archetype_specialty_choice_slot = enactor.pf2_archetypeinfo || {}
                    to_assign['archetype specialty choice'].each_pair do |choice_archetype, _choice_info|
                      if archetype_specialty_choice_slot['archetype1'] == choice_archetype
                        archetype_specialty_choice_slot['archetype_specialty_choice1'] = ""
                      elsif archetype_specialty_choice_slot['archetype2'] == choice_archetype
                        archetype_specialty_choice_slot['archetype_specialty_choice2'] = ""
                      elsif archetype_specialty_choice_slot['archetype3'] == choice_archetype
                        archetype_specialty_choice_slot['archetype_specialty_choice3'] = ""
                      elsif archetype_specialty_choice_slot['archetype4'] == choice_archetype
                        archetype_specialty_choice_slot['archetype_specialty_choice4'] = ""
                      end
                    end
                    enactor.pf2_archetypeinfo = archetype_specialty_choice_slot
                  end
                end
              end
            end
          end
        end

        enactor.advancing = false
        enactor.pf2_advancement = {}
        enactor.pf2_to_assign = {}

        enactor.save

        client.emit_success t('pf2e.adv_reset_ok')

      end
    end
  end
end
