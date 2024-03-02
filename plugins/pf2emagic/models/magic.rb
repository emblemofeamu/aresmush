module AresMUSH
  class PF2Magic < Ohm::Model
    include ObjectModel

    attribute :focus_cantrips, :type => DataType::Hash, :default => {}
    attribute :focus_spells, :type => DataType::Hash, :default => {}
    attribute :focus_pool, :type => DataType::Hash, :default => { "max"=>0, "current"=>0 }
    attribute :last_refocus, :type => DataType::Time
    attribute :innate_spells, :type => DataType::Hash, :default => {}
    attribute :revelation_locked, :type => DataType::Boolean
    attribute :signature_spells, :type => DataType::Hash, :default => {}
    attribute :repertoire, :type => DataType::Hash, :default => {}
    attribute :spell_abil, :type => DataType::Hash, :default => {}
    attribute :spellbook, :type => DataType::Hash, :default => {}
    attribute :spells_per_day, :type => DataType::Hash, :default => {}
    attribute :spells_prepared, :type => DataType::Hash, :default => {}
    attribute :spells_today, :type => DataType::Hash, :default => {}
    attribute :tradition, :type => DataType::Hash, :default => { "innate"=>["innate", "trained"] }
    attribute :prepared_lists, :type => DataType::Hash, :default => {}
    attribute :divine_font

    reference :character, "AresMUSH::Character"


    ##### CLASS METHODS #####

    def self.get_magic_obj(char)
      char.magic
    end

    def self.get_create_magic_obj(char)
      obj = char.magic

      return obj if obj

      obj = PF2Magic.create(character: char)
      char.update(magic: obj)

      return obj
    end

    def self.find_spell_by_name(name)
      term = name.upcase

      list = Global.read_config('pf2e_spells').keys.select { |s| s.upcase.match? term }

      return t('pf2e.multiple_matches', :element => 'spell') if list.size > 1
      return t('pf2e.nothing_to_display', :elements => 'spells') if list.empty?
      return list
    end

    def self.update_magic(char, charclass, info, client, cleanup=false)
      magic = get_create_magic_obj(char)

      if cleanup
        # The cleanup flag is specified when the direction is to remove the magic from the character.

        info.each_pair do |key, value|
          case key
          when "spell_abil"
            spell_abil = magic.spell_abil
            spell_abil.delete charclass
            magic.update(spell_abil: spell_abil)
          when "tradition"
            # magic.tradition structure: { charclass => [ trad, prof ] }
            tradition = magic.tradition
            value.each_pair do |trad, prof|
              tradition.delete charclass
            end

            magic.update(tradition: tradition)
          when "spells_per_day"
            # Structure: { charclass => {"cantrip" => 5, 1 => 3, 2 => 1} }
            spells_per_day = magic.spells_per_day

            value.each_pair do |level, num|
              new_num = (spells_per_day[level] - num).clamp(0,999)
              spells_per_day.delete(level) if new_num.zero?
            end

            magic.update(spells_per_day: spells_per_day)
          when "focus_pool"
            pool = magic.focus_pool

            new_max_pool = Pf2emagic.get_max_focus_pool(char, -value)
            pool["max"] = new_max_pool
            magic.update(focus_pool: pool)
          when "repertoire"
            to_assign = char.pf2_to_assign
            rep = magic.repertoire
            rep_c = rep['charclass']

            # Remove any spells already assigned for repertoire.

            to_assign['repertoire'].each_pair do |level, item|
              ary = rep[level]

              item.each do |s|
                next if s == "open"
                ary.delete s
              end

              rep_c[level] = ary

            end

            rep = rep_c['charclass']
            magic.update(repertoire: rep)

            to_assign.delete "repertoire"

            char.update(pf2_to_assign: to_assign)
          when "focus_spell"
            # focus spell structure: { "devotion" => [spell, spell, spell], "revelation" => [spell] }

            focus_spells = magic.focus_spells

            value.each_pair do |fstype, spell_list|
              fs_by_type = focus_spells[fstype] ? focus_spells[fstype] : []
              fs_by_type = (fs_by_type - spell_list).uniq
              focus_spells[fstype] = fs_by_type
            end

            magic.update(focus_spells: focus_spells)
          when "focus_cantrip"
            # Structure identical to focus_spells, kept separate because they are cast differently.

            focus_cantrips = magic.focus_cantrips

            value.each_pair do |fstype, spell_list|
              fs_by_type = focus_cantrips[fstype] ? focus_cantrips[fstype] : []
              fs_by_type = (fs_by_type - spell_list).uniq
              focus_cantrips[fstype] = fs_by_type
            end

            magic.update(focus_cantrips: focus_cantrips)
          when "spellbook"
            to_assign = char.pf2_to_assign
            sb = magic.spellbook
            sb_c = sb['charclass']

            # Remove any spells already assigned.

            to_assign['spellbook'].each_pair do |level, item|
              ary = sb[level]

              item.each do |s|
                next if s == "open"
                ary.delete s
              end

              sb_c[level] = ary

            end

            sb = sb_c['charclass']
            magic.update(spellbook: sb)

            to_assign.delete "spellbook"

            char.update(pf2_to_assign: to_assign)
          when "addspell"
            # Addspell means to add a specific spell to the spellbook. Adding spells to be chosen
            # should be the "spellbook" key.
            # Structure of value for addspell key: { level => [ spell ] }

            spellbook = magic.spellbook

            # Initialize spellbook for class if not already present.
            csb = spellbook[charclass]

            value.each do |level, spell_list|
              list = csb[level]

              spell_list.each do |item|
                list.delete item
              end

              csb[level] = list
            end

            spellbook[charclass] = csb
            magic.update(spellbook: spellbook)
          when "signature_spell"
            # This key means that the character needs to pick a spell from their repertoire as a signature spell.
            # Structure of value: { level to pick from => number of spells to add }
            # Use to_assign["signature"]
          when "innate_spell"
            # Structure of innate spells: {spell name => { 'level' => <level>, 'tradition' => tradition, 'cast_stat' => cast_stat}}

            ilist = magic.innate_spells
            key = value.delete('name')

            ilist[key] = value

            magic.update(innate_spells: ilist)

          else
            client.emit_ooc "Unknown key #{key} in update_magic. Please inform staff."
          end
        end
      else
        # Do this if the direction is to add.
        info.each_pair do |key, value|
          case key
          when "spell_abil"
            spell_abil = magic.spell_abil
            spell_abil[charclass] = value
            magic.update(spell_abil: spell_abil)
          when "tradition"
            # magic.tradition structure: { charclass => [ trad, prof ] }
            tradition = magic.tradition
            value.each_pair do |trad, prof|
              tradition[charclass] = [ trad, prof ]
            end

            magic.update(tradition: tradition)
          when "spells_per_day"
            # Structure: { charclass => {"cantrip" => 5, 1 => 3, 2 => 1} }
            spells_per_day = magic.spells_per_day
            spd_for_class = spells_per_day[charclass] ? spells_per_day[charclass] : {}

            value.each_pair do |level, num|
              spd_for_class[level] = num
            end

            spells_per_day[charclass] = spd_for_class

            magic.update(spells_per_day: spells_per_day)
          when "focus_pool"
            pool = magic.focus_pool

            new_max_pool = Pf2emagic.get_max_focus_pool(char, value)
            pool["max"] = new_max_pool
            magic.update(focus_pool: pool)
          when "repertoire"
            # Spells need to be chosen, redirect to to_assign

            to_assign = char.pf2_to_assign

            assignment_list = {}
            value.each_pair do |level, num|
              ary = Array.new(num, "open")
              assignment_list[level] = ary
            end

            to_assign["repertoire"] = assignment_list

            char.update(pf2_to_assign: to_assign)
          when "focus_spell"
            # focus spell structure: { "devotion" => [spell, spell, spell], "revelation" => [spell] }

            focus_spells = magic.focus_spells

            value.each_pair do |fstype, spell_list|
              fs_by_type = focus_spells[fstype] ? focus_spells[fstype] : []
              fs_by_type = (fs_by_type + spell_list).uniq
              focus_spells[fstype] = fs_by_type
            end

            magic.update(focus_spells: focus_spells)
          when "focus_cantrip"
            # Structure identical to focus_spells, kept separate because they are cast differently.

            focus_cantrips = magic.focus_cantrips

            value.each_pair do |fstype, spell_list|
              fs_by_type = focus_cantrips[fstype] ? focus_cantrips[fstype] : []
              fs_by_type = (fs_by_type + spell_list).uniq
              focus_cantrips[fstype] = fs_by_type
            end

            magic.update(focus_cantrips: focus_cantrips)
          when "spellbook"
            # Spells need to be chosen, redirect to to_assign

            to_assign = char.pf2_to_assign

            assignment_list = {}
            value.each_pair do |level, num|
              ary = Array.new(num, "open")
              assignment_list[level] = ary
            end

            to_assign["spellbook"] = assignment_list

            char.update(pf2_to_assign: to_assign)
          when "addspell"
            # Addspell means to add a specific spell to the spellbook. Adding spells to be chosen
            # should be the "spellbook" key.
            # Structure of value for addspell key: { level => [ spell ] }

            spellbook = magic.spellbook

            # Initialize spellbook for class if not already present.
            csb = spellbook[charclass] ? spellbook[charclass] : {}

            value.each do |level, spell_list|
              list = csb[level] ? csb[level] : []

              spell_list.each { |s| list << s }

              csb[level] = list
            end

            spellbook[charclass] = csb
            magic.update(spellbook: spellbook)
          when "signature_spell"
            # This key means that the character needs to pick a spell from their repertoire as a signature spell.
            # Structure of value: { level to pick from => number of spells to add }
            # Use to_assign["signature"]
          when "innate_spell"
            # Structure of innate spells: {spell name => { 'level' => <level>, 'tradition' => tradition, 'cast_stat' => cast_stat}}

            ilist = magic.innate_spells
            key = value.delete('name')

            ilist[key] = value

            magic.update(innate_spells: ilist)

          else
            client.emit_ooc "Unknown key #{key} in update_magic. Please inform staff."
          end
        end
      end

    end

    def self.delete_magic_stats(char, feat_name)
      # This helper is called when a character changes their mind about taking a feat that grants magic.

      magic = get_magic_obj(char)

      # This should never happen but it keeps the helper from crashing if it does.
      return nil unless magic

      # All this helper does is scrub magic_to_apply for this feat.

      pending_changes = magic.magic_to_apply

      removed_change = pending_changes.delete(feat_name)

      magic.update(magic_to_apply: removed_change)

    end

    def self.get_spell_dc(char, charclass, is_focus=false)

      # is_focus should be the focus spell type if given.

      magic = char.magic
      return nil unless magic

      if charclass == "innate"
        spell_abil = "Charisma"
      elsif is_focus
        spell_abil = get_focus_casting_stat(is_focus)
      else
        spell_abil = magic.spell_abil[charclass]
      end

      trad = magic.tradition[charclass]
      prof = trad[1]
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      abil_mod = Pf2eAbilities.abilmod(
        Pf2eAbilities.get_score char, spell_abil
      )

      10 + abil_mod + prof_bonus
    end

    def self.get_spell_attack_bonus(char, charclass, is_focus=false)

      # is_focus should be the focus spell type if given.

      magic = char.magic
      return nil unless magic

      if charclass == "innate"
        spell_abil = "Charisma"
      elsif is_focus
        spell_abil = get_focus_casting_stat(is_focus)
      else
        spell_abil = magic.spell_abil[charclass]
      end

      trad = magic.tradition[charclass]
      prof = trad[1]
      prof_bonus = Pf2e.get_prof_bonus(char, prof)

      abil_mod = Pf2eAbilities.abilmod(
        Pf2eAbilities.get_score char, spell_abil
      )

      abil_mod + prof_bonus
    end

    def self.factory_default(char)

      magic = char.magic

      magic.focus_cantrips = {}
      magic.focus_spells = {}
      magic.focus_pool = { "max"=>0, "current"=>0 }
      magic.innate_spells = {}
      magic.signature_spells = {}
      magic.repertoire = {}
      magic.spell_abil = {}
      magic.spellbook = {}
      magic.spells_per_day = {}
      magic.spells_prepared = {}
      magic.spells_today = {}
      magic.tradition = {}
      magic.prepared_lists = {}

      magic.save

    end

  end
end
