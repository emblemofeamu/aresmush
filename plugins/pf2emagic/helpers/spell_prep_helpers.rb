module AresMUSH
  module Pf2emagic

    def self.prepare_spell(spell, char, castclass, level, use_arcane_evo=false)
      # All validations are done in the helper.

      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)

      magic = char.magic

      cc = castclass.capitalize
      tradition = magic.tradition[cc]

      return t('pf2emagic.not_casting_class', :cc => cc) if !tradition

      prepared_cc_list = Global.read_config('pf2e_magic', 'prepared_casters')

      if !(prepared_cc_list.include? cc)
        if !use_arcane_evo
          return t('pf2emagic.does_not_prepare')
        end
      end

      # Can you prepare the level of spell you asked for?
      max_level = max_spell_level_available(char, cc)
      return t('pf2emagic.spell_exceeds_max_level') unless max_level

      return t('pf2emagic.spell_exceeds_max_level') if max_level.to_i < level.to_i

      # Get the spell info.
      spells = get_spell_details(spell)

      return spells if spells.is_a? String

      spell_name = spells[0]
      spell_details = spells[1]

      needs_spellbook = spell_details['traits'].intersect?(['rare', 'uncommon', 'unique'])

      if use_arcane_evo || needs_spellbook || cc == 'Wizard'
        is_in_spellbook = spellbook_check(magic, cc, level, spell_name)
        return t('pf2emagic.not_in_spellbook') unless is_in_spellbook[0]
        make_signature = is_in_spellbook[1]
      end

      return_msg = {
        "level" => level,
        "name" => spell_name,
        "caster class" => cc,
        "is_signature" => make_signature
      }

      if make_signature
        signature_spells = magic.signature_spells
        signature_spells["Arcane Evolution"] = [ spell_name ]
        magic.update(signature_spells: signature_spells)

        return return_msg
      end

      spell_trad = spell_details['tradition']

      return t('pf2emagic.cant_prepare_trad', :cc => cc) unless spell_trad.include? tradition[0].downcase

      spell_level = spell_details['base_level']

      # Level can be passed as nil, if it is, default to the base level of the spell.
      level = spell_level unless level

      return t('pf2emagic.cant_prepare_level') if (spell_level.to_i > level.to_i)

      if use_arcane_evo
        repertoire = obj.repertoire
        repertoire['Arcane Evolution'] = [ spells ]
        magic.update(repertoire: repertoire)

        return return_msg
      end

      spell_list = magic.spells_prepared
      spell_list_for_class = spell_list[cc] || {}
      spell_list_for_level = spell_list_for_class[level] || []

      max_spells_per_day = max_spells_per_day(char, cc, level)

      return t('pf2emagic.no_available_slots') unless spell_list_for_level.size < max_spells_per_day

      # If all checks succeed, prepare the spell and return a hash.

      spell_list_for_level << spell_name

      spell_list_for_class[level] = spell_list_for_level.sort
      spell_list[cc] = spell_list_for_class
      magic.update(spells_prepared: spell_list)

      return_msg

    end

    def self.unprepare_spell(spell, char, castclass, level)
      # All validations are done in the helper.
      return t('pf2emagic.not_caster') unless Pf2emagic.is_caster?(char)

      magic = char.magic
      cc = castclass.capitalize

      prepared_spells = magic.spells_prepared
      prep_spells_class = prepared_spells[cc]

      return t('pf2emagic.no_prepared_spells_class', :cc => cc.downcase) unless prep_spells_class

      prep_spells_level = prep_spells_class[level]
      return t('pf2emagic.no_prepared_spells_level') unless prep_spells_level

      # Because it is possible to prep the same spell multiple times, duplicates are accepted. Therefore,
      # we need to be able to delete just one at a time.

      # First, find the spell in question.

      spell_result = get_spell_details(spell)

      return spell_result if spell_result.is_a? String

      spname = spell_result[0]

      index = prep_spells_level.index(spname)
      return t('pf2emagic.not_prepared_at_level') unless index

      prep_spells_level.delete_at(index)

      prep_spells_class[level] = prep_spells_level
      prepared_spells[cc] = prep_spells_class
      magic.update(spells_prepared: prepared_spells)

      return nil
    end

    def self.spellbook_check(obj, castclass, level, spell)

      # Some classes may have their repertoire automatically written in a spellbook.
      # This is sometimes treated differently if prepared.

      prepare_ok = false
      make_signature = false

      spellbook = obj.spellbook[castclass]

      return [false, false] unless spellbook

      repertoire = obj.repertoire[castclass]

      book_spells_list = spellbook.values&.flatten

      rep_spells_list = repertoire ? repertoire[level] || [] : []

      is_in_book = book_spells_list.include? spell
      is_in_rep = rep_spells_list.include? spell

      prepare_ok = true if is_in_book

      make_signature = true if (is_in_book && is_in_rep)

      [prepare_ok, make_signature]
    end

    def self.max_spells_per_day(char, charclass, level)
      # Determines how many spells per day of that level the character can cast, for full spellcasting classes.
      # Not useful for focus-only classes.
      magic = char.magic
      return 0 unless magic

      # This will return nil for non-full casting classes.
      type = get_caster_type(charclass)
      return 0 unless type

      # This is the same whether you're a prepared or spontcaster.
      list = magic.spells_per_day[charclass]
      return 0 unless list

      sublist = list[level]

      sublist ? sublist : 0
    end

    def self.max_spell_level_available(char, charclass)
      # Determines max spell level available for full spellcasting classes.
      # Not useful for focus-only classes.
      magic = char.magic
      return nil unless magic

      # This will return nil for non-full casting classes.
      type = get_caster_type(charclass)
      return nil unless type

      # This is the same whether you're a prepared or spontcaster.
      list = magic.spells_per_day[charclass]
      return nil unless list

      levels_available = list.keys.sort { |a,b| a.to_i <=> b.to_i }

      levels_available.pop
    end

  end
end
