module AresMUSH
  module Pf2emagic

    def generate_blank_spell_list(obj)
      prepared_list = {}
      spells_per_day = obj.spells_per_day

      spells_per_day.each_pair do |level, count|
        list = Array.new(count, "open")

        prepared_list[level] = list
      end

      prepared_list
    end

    def self.get_caster_type(charclass)
      prepared = Global.read_config('pf2e_magic', 'prepared_casters')
      spont = Global.read_config('pf2e_magic', 'spontaneous_casters')

      return 'prepared' if prepared.include? charclass.capitalize
      return 'spontaneous' if spont.include? charclass.capitalize
      return nil

    end

    def deep_merge(second)
      merger = proc { |_, v1, v2| Hash === v1 && Hash === v2 ? v1.merge(v2, &merger) : Array === v1 && Array === v2 ? v1 | v2 : [:undefined, nil, :nil].include?(v2) ? v1 : v2 }
      merge(second.to_h, &merger)
    end

    def self.select_spell(char, charclass, level, old_spell, new_spell, common_only=false)
      # Do they get to pick a spell for this class at this time?
      to_assign = char.pf2_to_assign
      caster_type = get_caster_type(charclass)
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

      # Is new_spell of the level specified in level?
      return t('pf2emagic.incorrect_spelllevel_specified', :spell => to_add, :level => level ) if !deets["base_level"].to_i == level.to_i

      # Can the class they specified cast the spell they want?
      magic = char.magic
      charclass_trad = magic.tradition[charclass]

      return t('pf2emagic.cant_cast_as_class') unless (charclass_trad && caster_type)

      charclass_can_cast = deets['tradition'].include? charclass_trad[0]
      return t('pf2emagic.class_does_not_get_spell') unless charclass_can_cast

      # Can they learn that level of spell?
      # This is assumed to be true if the base level of the spell is a key in either the to_assign hash for the list type
      # OR in the character's personal list.

      spbl = deets["base_level"].to_i
      new_spells_for_level = new_spells_to_assign[level.to_s]


      return t('pf2emagic.cant_prepare_level') if spbl > level.to_i
      return t('pf2emagic.no_new_spells_at_level') unless new_spells_for_level

      # Do they already have that spell on their list of to_assign
      return t('pf2emagic.cg_spell_spell_already_on_list_to_assign') if new_spells_to_assign[level.to_s].include? to_add

      # At this point, the spell choice is deemed valid. If old_spell is true, they're swapping. Can they do that?

      if old_spell
        list = hash.keys
        to_replace = old_spell.upcase
        to_remove = list.select { |s| s.upcase == to_replace.upcase }
        i = new_spells_for_level.index to_remove.first
        return t('pf2emagic.not_in_list') unless i
      else
        i = new_spells_for_level.index "open"
        return t('pf2emagic.no_available_slots') unless i
      end

      # Okay. Do the swap or assignment.
      # new_spells_for_level.delete_at(i).push(to_add).sort
      new_spells_for_level[i] = to_add
      new_spells_for_level.sort
      new_spells_to_assign[level] = new_spells_for_level
      to_assign[sp_list_type] = new_spells_to_assign
      char.update(pf2_to_assign: to_assign)

      # Also add to magic spellbook object
      csb = char.magic.spellbook
      old_csb = char.magic.spellbook
      Global.logger.debug csb
      Global.logger.debug old_csb


      # Build spellbook, if needed.
      csb[charclass].nil? ? csb = { charclass => {} } : {}
      csb[charclass][level].nil? ? csb[charclass] = { level => [] } : {}
    

      # If spell already exists within the level, send it packing
      if old_spell
          list = hash.keys
          to_replace = old_spell.upcase
          to_remove = list.select { |s| s.upcase == to_replace.upcase }
          csb[charclass][level].delete(to_remove.first)
      end

      # Add the spell to the level in spellbook
      current_spells_at_level = csb[charclass][level]
      current_spells_at_level.append(to_add)
      current_spells_at_level.sort
      csb[charclass][level] = current_spells_at_level

      # Create the new spellbook
      Global.logger.debug csb
      Global.logger.debug old_csb
    
      new_spellbook = old_csb.deep_merge(csb)
      Global.logger.debug new_spellbook

      # Commit the change to the character
      char.magic.update(spellbook: new_spellbook)
      return nil
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

      msg << t('pf2emagic.choose_divine_font') if to_assign['divine font']

    end
  end
end
