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

    def get_focus_casting_stat(stype)
      Global.read_config('pf2e_magic', 'focus_casting_stat', stype)
    end

    def self.get_caster_type(charclass)
      prepared = Global.read_config('pf2e_magic', 'prepared_casters')
      spont = Global.read_config('pf2e_magic', 'spontaneous_casters')

      return 'prepared' if prepared.include? charclass
      return 'spontaneous' if spont.include? charclass
      return nil

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
      list = hash.keys.map { |s| s.upcase }
      to_find = new_spell.upcase
      match = list.select { |s| s == to_find }

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

      # At this point, the spell choice is deemed valid. If old_spell is true, they're swapping. Can they do that?

      if old_spell
        to_replace = old_spell.upcase
        to_remove = list.select { |s| s == to_replace }
        i = new_spells_for_level.index to_remove
        return t('pf2emagic.not_in_list') unless i
      else
        i = new_spells_for_level.index "open"
        return t('pf2emagic.no_available_slots') unless i
      end

      # Okay. Do the swap or assignment.
      new_spells_for_level.delete_at(i).push(to_add).sort
      new_spells_to_assign[level] = new_spells_for_level
      to_assign[sp_list_type] = new_spells_to_assign
      char.update(pf2_to_assign: to_assign)

      return nil
    end

    def self.find_common_spells
      Global.read_config('pf2e_spells').select { |k,v| v['traits'].include? 'common' }
    end

    def self.cg_magic_warnings(magic)

      msg = []

      # Should yell if the magic object did not get created.
      msg << t('pf2emagic.config_error', :code => "NO OBJECT") unless magic

    end
  end
end
