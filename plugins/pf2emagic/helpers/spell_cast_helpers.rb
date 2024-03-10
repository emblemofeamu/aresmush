module AresMUSH
  module Pf2emagic

    def self.get_focus_casting_stat(stype)
      Global.read_config('pf2e_magic', 'focus_casting_stat', stype)
    end

    def self.cast_prepared_spell(char, magic_obj, charclass, spell, level=nil)
      caster_stats = get_caster_stats(char, magic_obj, charclass)

      return caster_stats if caster_stats.is_a? String

      char_spells_today = magic.prepared_spells[charclass]

      spells = get_spells_by_name(spell)

      # if the spell name is ambiguous and the level is not specified, the command will fail.
      # If level is specified, the code will try to find a spell matching the string at that level in the
      # prepared list. If that fails, the command will fail.

      if spells.is_a? Array
        return t('pf2emagic.no_such_spell') if spells.empty?
        return t('pf2emagic.multiple_matches', :item => 'spell') if (spells.size > 1 && !level)
        find_spell_at_level = spells && char_spells_today[level]

        # This is where you left off. Determine whether there is a single spell in find_spell_at_level and take
        # that if there is.
      end



    end

    def self.get_caster_stats(char, magic_obj, charclass)

      # Can this character cast as this class?
      cast_stats = magic_obj.tradition[charclass]

      return t('pf2emagic.not_casting_class', :cc => charclass) unless cast_stats

      # Return a hash of all the pieces of their casting stats for that class.

      {
        'tradition' => cast_stats.keys.first,
        'prof_level' => cast_stats.values.first,
        'spell_abil' => magic_obj.spell_abil[charclass],
        'modifier' => Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, spell_abil))
      }

    end

  end
end
