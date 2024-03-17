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

    def self.select_spell(char, charclass, level, old_spell, new_spell, common_only=false)

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

      charclass_can_cast = deets['tradition'].include? charclass_trad[0]

      return t('pf2emagic.class_does_not_get_spell') unless charclass_can_cast

      # Can they learn that level of spell?
      # This is assumed to be true if the base level of the spell is a key in either the to_assign hash for the list type
      # OR in the character's personal list.

      spbl = deets["base_level"].to_i
      new_spells_for_level = new_spells_to_assign[level]

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
