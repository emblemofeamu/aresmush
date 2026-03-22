module AresMUSH
  module Pf2emagic

    def self.generate_blank_spell_list(obj, charclass)

      spells_per_day = obj.spells_per_day
      class_spells_per_day = spells_per_day[charclass]

      class_spells_per_day.each_pair do |level, count|
        list = Array.new(count, "open")

        prepared_list[level] = list
      end

    end

    def self.get_caster_type(charclass)
      prepared = Array(Global.read_config('pf2e_magic', 'prepared_casters'))
      spont = Array(Global.read_config('pf2e_magic', 'spontaneous_casters'))
      prepared_arch = Array(Global.read_config('pf2e_magic', 'prepared_archetypes'))
      spont_arch = Array(Global.read_config('pf2e_magic', 'spontaneous_archetypes'))

      key = charclass.to_s.downcase
      prepared_keys = (prepared + prepared_arch).map { |cc| cc.to_s.downcase }
      spont_keys = (spont + spont_arch).map { |cc| cc.to_s.downcase }

      return 'prepared' if prepared_keys.include?(key)
      return 'spontaneous' if spont_keys.include?(key)
      return nil

    end

    def self.check_spell(char, charclass, level, term, common_only=false)

      hash = common_only ? find_common_spells : Global.read_config('pf2e_spells')
      match = hash.keys.select { |s| s.downcase == term.downcase }

      return t('pf2emagic.no_such_spell') if match.empty?
      return t('pf2emagic.multiple_matches', :item => 'spell') if (match.size > 1)

      spell = match.first
      deets = hash[spell]

      # Can the class they specified cast the spell they want?
      magic = char.magic
      charclass_trad = magic.tradition[charclass]
      caster_type = get_caster_type(charclass)

      return t('pf2emagic.cant_cast_as_class') unless (charclass_trad && caster_type)

      # A spell that does not have a tradition key cannot be put in a spellbook.
      return t('pf2emagic.not_spellbook_eligible') unless deets['tradition']

      charclass_can_cast = deets['tradition'].include? charclass_trad[0]

      return t('pf2emagic.class_does_not_get_spell') unless charclass_can_cast

      # Can they take the spell at the level specified?

      spbl = deets["base_level"].to_i
      level_is_cantrip = (level.to_s.downcase == 'cantrip' || level.to_i.zero?)
      spell_is_cantrip = spbl.zero?

      return t('pf2emagic.cant_learn_cantrip_slot') if spell_is_cantrip && !level_is_cantrip
      return t('pf2emagic.cant_learn_spell_cantrip') if !spell_is_cantrip && level_is_cantrip
      return t('pf2emagic.cant_prepare_level') if spbl > level.to_i

      [ spell, deets ]
    end

    def self.select_gated_spell(char, charclass, level, old_spell, new_spell, gate, is_dedication=false, common_only=false)
      # Caster type check.
      caster_type = get_caster_type(charclass)

      return t('pf2emagic.no_new_spells') unless caster_type

      # Do they need to pick a gated spell for the gate specified?
      # The name of the sublist in to_assign is the gate + "spell".
      to_assign = char.pf2_to_assign
      sp_list_type = gate + " spell"

      new_spells_to_assign = to_assign[sp_list_type]

      return t('pf2emagic.no_new_spells') unless new_spells_to_assign

      hash = common_only ? find_common_spells : Global.read_config('pf2e_spells')
      match = hash.keys.select { |s| s.downcase == new_spell.downcase }

      return t('pf2emagic.no_such_spell') if match.empty?
      return t('pf2emagic.multiple_matches', :item => 'spell') if (match.size > 1)

      # Spell's valid. Does it pass the gate?
      to_add = match.first

      pass_gate = can_take_gated_spell?(char, charclass, level, to_add, gate, is_dedication)
      return t('pf2emagic.spell_not_eligible', :gate => gate) unless pass_gate

      # If we have reached this point, it's time to add the spell.
      # Stuff into to_assign for tracking of what got bought when.
      magic = char.magic

      new_spells_to_assign = to_add
      to_assign[sp_list_type] = new_spells_to_assign
      char.update(pf2_to_assign: to_assign)

      # Stuff into spellbook or repertoire as appropriate.
      # Note that this function should not be used for uncommon or rare spells going in a spellbook.
      # That is expected to be handled by admin/set.

      if !(old_spell.blank?)
        # Find the correct name for the old spell.
        # This will fall to not_in_list if they got the wrong match due to lack of specificity.
        old_spname = get_spells_by_name(old_spell).first

        return t('pf2emagic.spell_to_delete_not_found') unless old_spname
      end

      if caster_type == "prepared"
        csb = magic.spellbook
        csb_cc = csb[charclass] || {}
        csb_level = csb_cc[level] || []
        # There might be a spell swap.
        if old_spname
          csb_i = csb_level.index old_spname
          # Probably an unnecessary check, but it flags if spells are not being added properly.
          return t('pf2emagic.spell_to_delete_not_found') unless csb_i

          csb_level[csb_i] = to_add
        else
          csb_level << to_add
        end

        csb_cc[level] = csb_level
        csb[charclass] = csb_cc
        magic.update(spellbook: csb)
      else
        csb = magic.repertoire
        csb_cc = csb[charclass] || {}
        csb_level = csb_cc[level] || []
        if old_spname
          csb_i = csb_level.index old_spname
          # Probably an unnecessary check, but it flags if spells are not being added properly.
          return t('pf2emagic.spell_to_delete_not_found') unless csb_i

          csb_level[csb_i] = to_add
        else
          csb_level << to_add
        end

        csb_cc[level] = csb_level
        csb[charclass] = csb_cc
        magic.update(repertoire: csb)
      end

      # The calling handler should interpret a nil response as a successful add and a String as a failure.
      return nil
    end

    def self.select_spell(char, charclass, level, old_spell, new_spell, is_gated=false, common_only=false)
      # Handling for gated spells is diverted to another function. is_gated is either
      # false or the name of the gate.

      if is_gated
        msg = select_gated_spell(char, charclass, level, old_spell, new_spell, is_gated, common_only)
        return msg
      end

      # This command is only used by full spellcasting classes.
      caster_type = get_caster_type(charclass)

      return t('pf2emagic.no_new_spells') unless caster_type

      # Do they get to pick a spell for this class at this time?
      to_assign = char.pf2_to_assign
      sp_list_type = (caster_type == "prepared" ? "spellbook" : "repertoire")
      new_spells_to_assign = to_assign[sp_list_type]

      return t('pf2emagic.no_new_spells') unless new_spells_to_assign

      # Is new_spell a valid, unique choice?
      # Only common spells are available in cg/advancement, set last argument to true to enforce
      hash = common_only ? find_common_spells : Global.read_config('pf2e_spells')
      match = hash.keys.select { |s| s.downcase == new_spell.downcase }

      return t('pf2emagic.no_such_spell') if match.empty?
      return t('pf2emagic.multiple_matches', :item => 'spell') if (match.size > 1)

      to_add = match.first
      deets = hash[to_add]

      # Can the class they specified cast the spell they want?
      magic = char.magic
      charclass_trad = magic.tradition[charclass]

      return t('pf2emagic.cant_cast_as_class') unless (charclass_trad && caster_type)

      # A spell that does not have a tradition key cannot be put in a spellbook.
      return t('pf2emagic.not_spellbook_eligible') unless deets['tradition']

      charclass_can_cast = deets['tradition'].include? charclass_trad[0]

      return t('pf2emagic.class_does_not_get_spell') unless charclass_can_cast

      # Can they learn that level of spell?
      # This is assumed to be true if the base level of the spell is a key in either the to_assign hash for the list type
      # OR in the character's personal list.

      spbl = deets["base_level"].to_i
      level_is_cantrip = (level.to_s.downcase == 'cantrip' || level.to_i.zero?)
      spell_is_cantrip = spbl.zero?
      new_spells_for_level = new_spells_to_assign[level]

      return t('pf2emagic.cant_learn_cantrip_slot') if spell_is_cantrip && !level_is_cantrip
      return t('pf2emagic.cant_learn_spell_cantrip') if !spell_is_cantrip && level_is_cantrip
      return t('pf2emagic.cant_prepare_level') if spbl > level.to_i

      return t('pf2emagic.no_new_spells_at_level') unless new_spells_for_level

      # Do they already have that spell on their list of to_assign?
      return t('pf2emagic.spell_already_on_list_to_assign') if new_spells_to_assign[level].include? to_add

      # At this point, the spell choice is deemed valid. If old_spell is true, they're swapping. Can they do that?

      if !(old_spell.blank?)
        # Find the correct name for the old spell.
        # This will fall to not_in_list if they got the wrong match due to lack of specificity.
        old_spname = get_spells_by_name(old_spell).first

        return t('pf2emagic.spell_to_delete_not_found') unless old_spname

        i = new_spells_for_level.index old_spname
        return t('pf2emagic.not_in_list') unless i
      else
        old_spname = nil
        i = new_spells_for_level.index "open"
        return t('pf2emagic.no_available_slots') unless i
      end

      # If we have reached this point, it's time to add the spell.
      # Stuff into to_assign for tracking of what got bought when.
      new_spells_for_level[i] = to_add
      new_spells_for_level.sort
      new_spells_to_assign[level] = new_spells_for_level
      to_assign[sp_list_type] = new_spells_to_assign
      char.update(pf2_to_assign: to_assign)

      # Stuff into spellbook or repertoire as appropriate.
      # Note that this function should not be used for uncommon or rare spells going in a spellbook.
      # That is expected to be handled by admin/set.

      if caster_type == "prepared"
        csb = magic.spellbook
        csb_cc = csb[charclass] || {}
        csb_level = csb_cc[level] || []
        # There might be a spell swap.
        if old_spname
          csb_i = csb_level.index old_spname
          # Probably an unnecessary check, but it flags if spells are not being added properly.
          return t('pf2emagic.spell_to_delete_not_found') unless csb_i

          csb_level[csb_i] = to_add
        else
          csb_level << to_add
        end

        csb_cc[level] = csb_level
        csb[charclass] = csb_cc
        magic.update(spellbook: csb)
      else
        csb = magic.repertoire
        csb_cc = csb[charclass] || {}
        csb_level = csb_cc[level] || []
        if old_spname
          csb_i = csb_level.index old_spname
          # Probably an unnecessary check, but it flags if spells are not being added properly.
          return t('pf2emagic.spell_to_delete_not_found') unless csb_i

          csb_level[csb_i] = to_add
        else
          csb_level << to_add
        end

        csb_cc[level] = csb_level
        csb[charclass] = csb_cc
        magic.update(repertoire: csb)
      end

      # The calling handler should interpret a nil response as a successful add and a String as a failure.
      return nil
    end

    def self.select_innate_spell(char, level, old_spell, new_spell, common_only=false)
      magic = char.magic
      innate_spells = magic.innate_spells || {}

      return t('pf2emagic.innate_no_new_spells') if innate_spells.empty?

      old_spname = nil

      if !(old_spell.blank?)
        old_spname = get_spells_by_name(old_spell).first
        return t('pf2emagic.innate_spell_to_delete_not_found') unless old_spname

        source_info = innate_spells[old_spname]
        return t('pf2emagic.innate_spell_to_delete_not_found') unless source_info
      else
        source_info = innate_spells['open']
        return t('pf2emagic.innate_no_new_spells') unless source_info
      end

      hash = common_only ? find_common_spells : Global.read_config('pf2e_spells')
      match = hash.keys.select { |s| s.downcase == new_spell.downcase }

      return t('pf2emagic.innate_no_such_spell') if match.empty?
      return t('pf2emagic.innate_multiple_matches', :item => 'spell') if (match.size > 1)

      to_add = match.first
      return t('pf2emagic.innate_spell_already_on_list_to_assign') if innate_spells.key?(to_add)

      deets = hash[to_add]

      return t('pf2emagic.innate_not_spell_eligible') unless deets['tradition']

      tradition = source_info['tradition']
      return t('pf2emagic.innate_tradition_mismatch') unless deets['tradition'].include?(tradition)

      spbl = deets['base_level'].to_i
      level_is_cantrip = (level.to_s.downcase == 'cantrip' || level.to_i.zero?)
      spell_is_cantrip = spbl.zero?

      return t('pf2emagic.innate_cant_learn_cantrip_slot') if spell_is_cantrip && !level_is_cantrip
      return t('pf2emagic.innate_cant_learn_spell_cantrip') if !spell_is_cantrip && level_is_cantrip
      return t('pf2emagic.innate_cant_prepare_level') if spbl > level.to_i

      slot_level = source_info['level']
      slot_is_cantrip = (slot_level.to_s.downcase == 'cantrip' || slot_level.to_i.zero?)
      return t('pf2emagic.innate_cant_prepare_level') if slot_is_cantrip != level_is_cantrip
      return t('pf2emagic.innate_cant_prepare_level') if !slot_is_cantrip && slot_level.to_i != level.to_i

      if old_spname
        innate_spells.delete(old_spname)
      else
        innate_spells.delete('open')
      end

      innate_spells[to_add] = source_info
      magic.update(innate_spells: innate_spells)

      nil
    end

    def self.find_common_spells
      Global.read_config('pf2e_spells').select { |k,v| !v['traits'].include? 'uncommon' or !v['traits'].include? 'rare' or !v['traits'].include? 'unique' }
    end

    def self.get_spells_by_name(term)
      spell_list = Global.read_config('pf2e_spells').keys

      # Return an exact match if found.
      exact_match = spell_list.index {|spell| spell.downcase == term.downcase}

      return [ spell_list[exact_match] ] if exact_match

      # If not, return a list of partial matches.
      spell_list.select {|spell| spell.downcase.match? term.downcase}
    end

    def self.cg_magic_warnings(magic, to_assign)
      msg = []

      # Should yell if the magic object did not get created.
      msg << t('pf2emagic.config_error', :code => "NO OBJECT") unless magic

      msg << t('pf2emagic.choose_divine_font') if to_assign['divine font'].is_a? Array

      has_school_spell = to_assign['school spell']

      if has_school_spell
        specialize_info = magic&.character&.pf2_base_info&.[]('specialize_info')
        msg << t('pf2emagic.choose_school_spell', :wizard_school => specialize_info) if has_school_spell == 'school'
      end

      innate_spells = magic&.innate_spells || {}
      open_innate = innate_spells.select { |k, _| k.to_s.casecmp?('open') }

      if !open_innate.empty?
        labels = open_innate.values.map do |info|
          level_label = info['level'].to_s.downcase
          is_cantrip = (level_label == 'cantrip' || level_label == '0')
          tradition = Array(info['tradition']).first
          tradition_label = tradition.to_s.empty? ? 'unknown tradition' : tradition.to_s

          if is_cantrip
            "innate cantrip (#{tradition_label})"
          else
            "#{Pf2emagic.ordinal_level(level_label)}-level spell (#{tradition_label})"
          end
        end

        counts = labels.tally
        details = counts.map do |label, count|
          plural_label = Pf2emagic.pluralize_label(label, count)
          "#{count} #{plural_label}"
        end

        details_text = Pf2emagic.join_with_and(details)
        msg << t('pf2emagic.cg_innate_spells', :details => details_text)
      end

    end

    def self.can_take_gated_spell?(char, charclass, level, term, gate, is_dedication=false)
      # Used for spells with limited choices.
      # Does the spell exist?
      spell = get_spell_details(term)
      return false unless spell.is_a? Array

      # Spell's valid. Assemble the details.
      spdeets = spell[1]

      # Can the character take that spell at that level?
      base_level = spdeets['base_level'].to_i
      level_is_cantrip = (level.to_s.downcase == 'cantrip' || level.to_i.zero?)
      spell_is_cantrip = base_level.zero?

      return false if spell_is_cantrip && !level_is_cantrip
      return false if !spell_is_cantrip && level_is_cantrip

      return false unless level.to_i >= base_level

      max_level_can_cast = ((char.pf2_level + 1) / 2).floor.clamp(1,10)
      max_level_can_cast = (max_level_can_cast / 2).floor.clamp(1,10) if is_dedication

      return false unless max_level_can_cast >= level.to_i

      # Tradition check
      magic = char.magic

      trad_info = magic.tradition[charclass]
      return false unless trad_info

      tradition = trad_info[0]
      return false unless spdeets['tradition'].include? tradition
      # Gate check

      case gate
      when 'school'
        # The school gate checks that the spell in question is of your specialist school.
        char_school = char.pf2_base_info['specialize_info'].downcase

        passes_gate = spdeets['traits'].include? char_school
      else
        # Fail any gate not recognized.
        passes_gate = false
      end

      passes_gate
    end

    def self.ordinal_level(level_label)
      level = level_label.to_i

      return level_label if level.zero?

      mod_100 = level % 100
      suffix = if mod_100.between?(11, 13)
        'th'
      else
        case level % 10
        when 1
          'st'
        when 2
          'nd'
        when 3
          'rd'
        else
          'th'
        end
      end

      "#{level}#{suffix}"
    end

    def self.join_with_and(items)
      return '' if items.empty?
      return items.first if items.size == 1
      return "#{items[0]} and #{items[1]}" if items.size == 2

      "#{items[0..-2].join(', ')}, and #{items[-1]}"
    end

    def self.pluralize_label(label, count)
      return label if count == 1

      if label.include?('cantrip')
        label.sub('cantrip', 'cantrips')
      elsif label.include?(' spell')
        label.sub(' spell', ' spells')
      else
        label + 's'
      end
    end
  end
end
