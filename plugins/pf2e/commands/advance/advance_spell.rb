module AresMUSH
  module Pf2e

    class PF2AdvanceSpellCmd
      include CommandHandler

      attr_accessor :type, :level, :value, :old_value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.type = downcase_arg(args.arg1)
        self.level = trim_arg(args.arg2)
        spells = trimmed_list_arg(args.arg3,"/")

        if spells
          if spells[1]
            self.value = spells[1]
            self.old_value = spells[0]
          else
            self.value = spells[0]
          end
        end

      end

      def required_args
        [ self.type, self.level, self.value ]
      end

      def check_advancing
        return nil if enactor.advancing
        return t('pf2e.not_advancing')
      end

      def handle
        # Do they have one of these to select?

        to_assign = enactor.pf2_to_assign

        charclass = enactor.pf2_base_info['charclass']
        type_option = to_assign[self.type]

        unless type_option
          if self.type == charclass.downcase
            client.emit_failure t('pf2e.adv_spell_wrong_type', :class => charclass)
            return
          end

          client.emit_failure t('pf2e.adv_not_an_option')
          return
        end

        level = self.level.to_i.zero? ? 'cantrip' : self.level

        list = self.type == "spellbook" ? type_option : type_option[level]

        if self.type == "innate"
          unless list.is_a?(Array)
            client.emit_failure t('pf2emagic.innate_no_new_spells')
            return
          end

          result = resolve_innate_spell(level, self.value, list)
          if result.is_a?(String)
            client.emit_failure result
            return
          end

          spell = result

          update_innate_advancement(spell, list, type_option, level)

          client.emit_success t('pf2e.add_ok', :item => spell, :list => self.type)
          return
        end


        # Now we have to figure out if we have an open slot.
        open_slot = list.index "open"

        if open_slot
          old = "open"
        elsif self.old_value
          old = list.select {|s| s.downcase.match? self.old_value.downcase}.first

          unless old
            client.emit_failure t('pf2e.not_in_list', :option => self.old_value)
            return
          end

          open_slot = list.index old
        else
          client.emit_failure t('pf2e.no_free', :element => "#{self.type} slot")
          return
        end

        choice = Pf2emagic.check_spell(enactor, charclass, level, self.value, true)

        if choice.is_a? String
          client.emit_failure choice
          return
        end

        spell = choice[0]

        if self.type == "signature"
          repertoire = Pf2e.preview_repertoire(enactor)
          rep_for_class = repertoire[charclass] || {}
          rep_spells_at_level = Array(rep_for_class[level])

          unless rep_spells_at_level.include?(spell)
            client.emit_failure t('pf2emagic.signature_not_in_repertoire', :level => level)
            return
          end
        end

        advancement = enactor.pf2_advancement

        # because Ruby is stupid and doesn't let you replace at an index directly.
        list.delete_at open_slot
        list << spell

        # Because I was stupid and repertoire is a Hash and spellbook is an array.

        if self.type == "spellbook"
          to_assign[self.type] = list
          advancement[self.type] = list
        elsif self.type == "repertoire" || self.type == "signature"
          type_option[level] = list

          to_assign[self.type] = type_option
          advancement[self.type] = type_option
        end

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign

        enactor.save

        client.emit_success t('pf2e.add_ok', :item => spell, :list => self.type)
      end

      def resolve_innate_spell(level, value, list)
        advancement = enactor.pf2_advancement || {}
        magic_stats = advancement['magic_stats'] || {}
        pending = magic_stats['innate_spell']

        return t('pf2emagic.innate_no_new_spells') unless pending

        names = Array(pending['name'])

        if self.old_value
          return t('pf2emagic.innate_spell_to_delete_not_found') unless names.any? { |n| n.to_s.casecmp?(self.old_value) }
        else
          return t('pf2emagic.innate_no_new_spells') unless names.any? { |n| n.to_s.downcase == 'open' }
        end

        open_slot = list.index "open"
        old = if open_slot
          "open"
        elsif self.old_value
          list.select { |s| s.to_s.downcase.match? self.old_value.downcase }.first
        else
          nil
        end

        return t('pf2emagic.innate_spell_to_delete_not_found') unless old

        hash = Pf2emagic.find_common_spells
        match = hash.keys.select { |s| s.downcase == value.downcase }

        return t('pf2emagic.innate_no_such_spell') if match.empty?
        return t('pf2emagic.innate_multiple_matches', :item => 'spell') if (match.size > 1)

        to_add = match.first
        return t('pf2emagic.innate_spell_already_on_list_to_assign') if list.any? { |s| s.to_s.casecmp?(to_add) }

        deets = hash[to_add]

        return t('pf2emagic.innate_not_spell_eligible') unless deets['tradition']

        tradition = pending['tradition']
        return t('pf2emagic.innate_tradition_mismatch') unless deets['tradition'].include?(tradition)

        spbl = deets['base_level'].to_i
        level_is_cantrip = (level.to_s.downcase == 'cantrip' || level.to_i.zero?)
        spell_is_cantrip = spbl.zero?

        return t('pf2emagic.innate_cant_learn_cantrip_slot') if spell_is_cantrip && !level_is_cantrip
        return t('pf2emagic.innate_cant_learn_spell_cantrip') if !spell_is_cantrip && level_is_cantrip
        return t('pf2emagic.innate_cant_prepare_level') if spbl > level.to_i

        slot_level = pending['level']
        slot_is_cantrip = (slot_level.to_s.downcase == 'cantrip' || slot_level.to_i.zero?)
        return t('pf2emagic.innate_cant_prepare_level') if slot_is_cantrip != level_is_cantrip
        return t('pf2emagic.innate_cant_prepare_level') if !slot_is_cantrip && slot_level.to_i != level.to_i

        to_add
      end

      def update_innate_advancement(spell, list, type_option, level)
        advancement = enactor.pf2_advancement || {}
        magic_stats = advancement['magic_stats'] || {}
        pending = magic_stats['innate_spell'] || {}

        names = Array(pending['name'])
        replace_index = if self.old_value
          names.index { |n| n.to_s.casecmp?(self.old_value) }
        else
          names.index { |n| n.to_s.downcase == 'open' }
        end

        return unless replace_index

        names[replace_index] = spell
        pending['name'] = names.size == 1 ? names.first : names
        magic_stats['innate_spell'] = pending
        advancement['magic_stats'] = magic_stats

        open_slot = list.index("open")
        open_slot = list.index { |s| s.to_s.casecmp?(self.old_value) } if open_slot.nil? && self.old_value

        if open_slot
          list.delete_at open_slot
          list << spell
        end

        type_option[level] = list
        to_assign = enactor.pf2_to_assign
        to_assign[self.type] = type_option
        advancement[self.type] = type_option

        enactor.pf2_advancement = advancement
        enactor.pf2_to_assign = to_assign
        enactor.save
      end
    end
  end
end
