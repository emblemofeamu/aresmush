module AresMUSH
  module Pf2e

    class PF2AdminSetCmd
      include CommandHandler

      attr_accessor :character, :item, :value

      def parse_args
        args = cmd.parse_args(ArgParser.arg1_slash_arg2_equals_arg3)

        self.character = trim_arg(args.arg1)
        self.item = downcase_arg(args.arg2)
        self.value = titlecase_list_arg(args.arg3)
      end

      def required_args
        [ self.character, self.item, self.value ]
      end

      def check_can_change_sheet
        return nil if enactor.has_permission?('manage_sheet')
        return t('dispatcher.not_allowed')
      end

      def handle
        char = Pf2e.get_character(self.character, enactor)

        if !char
          client.emit_failure t('pf2e.not_found')
          return
        end

      valid_instructions = %w{add delete}

        case self.item
        when "feat"
          # Expected structure of self.value: <feat type> add|delete <feat name>

          feat_type = self.value[0].downcase
          instruction = self.value[1].downcase
          details = Pf2e.get_feat_details(self.value[2])

          unless valid_instructions.include? instruction
            client.emit_failure t('pf2e.bad_instruction')
            return
          end

          if details.is_a? String
            client.emit_failure t('pf2e.not_unique')
            return
          end

          feat_name = details.first
          fdeets = details[1]

          valid_feat_types = Global.read_config('pf2e', 'valid_feat_types')

          if !(valid_feat_types.include? feat_type)
            client.emit_failure t('pf2e.bad_value', :item => 'feat type')
            return
          end

          char_feat_list = char.pf2_feats
          feat_sublist = char_feat_list[feat_type]

          if instruction == 'add'
            feat_sublist << feat_name
          elsif instruction == 'delete'
            # Feats can be duplicated, so it is necessary to delete only one at a time.
            i = feat_sublist.index(feat_name)
            feat_sublist.delete_at[i] if i
          else
            client.emit_failure t('pf2e.bad_value', :item => 'instruction')
            return
          end

          char_feat_list[feat_type] = feat_sublist.sort
          char.update(pf2_feats: char_feat_list)

          client.emit_success t('pf2e.updated_ok', :element => "Feat #{feat_name}", :char => char.name)

          feat_grants_stuff = fdeets['grants']

          if feat_grants_stuff
            if instruction == 'add'
              charclass = fdeets['assoc_charclass'] ? fdeets['assoc_charclass'] : char.pf2_base_info['charclass']
              Pf2e.do_feat_grants(enactor, feat_grants_stuff, charclass, client)
              client.emit_ooc "The assigned feat grants extra stuff. Processing."
            else
              client.emit_ooc "The assigned feat grants other things. You may need to do manual cleanup on the sheet."
            end
          end
        when "skill"
          # Expected structure of self.value: `<skill name> <proficiency level>`

          # Skills can be multi-word names, but prof is always the last word, so pop it off the end and the rest
          # is the skill name.

          new_prof = self.value.pop.downcase
          skname = self.value.join(" ")

          skill = Pf2eSkills.find_skill(skname, char)

          levels = %w(untrained trained expert master legendary)

          if !(levels.include? new_prof)
            client.emit_failure t('pf2e.bad_value', :item => 'proficiency level')
            return
          end

          # Skill object can be nil! Attempt to create if not found.

          if !skill
            skill_list = Global.read_config('pf2e_skills').keys

            if !(skill_list.include? skname)
              client.emit_failure t('pf2e.bad_skill', :name => skname)
              return
            end

            skill = Pf2eSkills.create_skill_for_char(skname, char)
          end

          skill.update(prof_level: new_prof)
          client.emit_success t('pf2e.updated_ok', :element => skill.name, :char => char.name)

        when "feature"
          # Expected structure of self.value: `[add|delete] <feature name>`
          # No validation of the feature in question is done.

          features = char.pf2_features
          instruction = value[0].downcase
          ftoadd = titlecase_arg(value[1])

          unless valid_instructions.include? instruction
            client.emit_failure t('pf2e.bad_instruction')
            return
          end

          if instruction == "add"
            features << ftoadd
          elsif instruction == "delete"
            i = features.each {|f| f.upcase}.index(ftoadd.upcase)

            if !i
              client.emit_failure t('pf2e.not_in_list', :option => ftoadd)
              return
            end

            features.delete_at(i)
          end

          char.update(pf2_features: features.sort)

          client.emit_success t('pf2e.updated_ok', :element => "Feature", :char => char.name)
        when "spellbook"
          # Expected structure of self.value: <charclass> [add|delete] <spell name> <spell level>

          castclass = self.value[0].downcase
          caster_type = Pf2emagic.get_caster_type(castclass)

          if !caster_type
            client.emit_failure t('pf2e.use_focus_keyword')
            return
          end

          instruction = self.value[1].downcase

          unless valid_instructions.include? instruction
            client.emit_failure t('pf2e.bad_instruction')
            return
          end

          spell_level = self.value[3].downcase
          spell = Pf2emagic.get_spells_by_name(self.value[2])

          unless spell.size == 1
            client.emit_failure t('pf2e.not_unique')
            return
          end

          spell = spell.first

          # Now it's time to do the adding.

          info = { 'addspellbook' => { spell_level => [ spell ]} }

          PF2Magic.update_magic(char, charclass, info, client)

        when 'repertoire'
          # Expected structure of self.value: <charclass> [add|delete] <spell name> <spell level>
          charclass = self.value[0].capitalize
          caster_type = Pf2emagic.get_caster_type(charclass.downcase)

          if !caster_type
            client.emit_failure t('pf2e.use_focus_keyword')
            return
          end

          instruction = self.value[1].downcase

          unless valid_instructions.include? instruction
            client.emit_failure t('pf2e.bad_instruction')
            return
          end

          spell_level = self.value[3].to_i.zero? ? 'cantrip' : self.value[3].to_i
          spell = Pf2emagic.get_spells_by_name(self.value[2])

          unless spell.size == 1
            client.emit_failure t('pf2e.not_unique')
            return
          end

          spell = spell.first

          if instruction == 'add'
            info = { 'addrepertoire' => { spell_level => spell }}
            PF2Magic.update_magic(char, charclass, info, client)
          elsif instruction == 'delete'
            magic = char.magic
            repertoire = magic.repertoire
            charclass_rep = repertoire[charclass]
            rep_level = charclass_rep[spell_level]
            rep_level.delete spell
            charclass_rep[spell_level] = rep_level
            repertoire[charclass] = charclass_rep
            magic.update(repertoire: repertoire)
          end

          client.emit_success t('pf2e.updated_ok', :char => char.name, :element => 'Repertoire')
        when "focus"
          # Expected structure of value: add|delete <charclass> cantrip|spell <spell name>

          charclass = self.value[1].capitalize
          instruction = self.value[0].downcase
          spell_type = self.value[2].downcase
          spell_name = titlecase_arg(self.value[3])

          unless valid_instructions.include? instruction
            client.emit_failure t('pf2e.bad_instruction')
            return
          end

          fspell_type = Global.read_config('pf2e_magic', 'focus_type_by_class', charclass)

          unless fspell_type
            client.emit_failure t('pf2e.bad_value', :item => 'character class')
            return
          end

          key = "focus_" + spell_type

          if instruction == 'add'
            value = { fspell_type => [ spell_name ]}
            spell_info = { key => value }
            PF2Magic.update_magic(char, charclass, spell_info, client)
          elsif instruction == 'delete'
            magic = char.magic
            if key == 'focus_cantrip'
              focus_list = magic.focus_cantrips
              fspell_list = focus_list[fspell_type]
              fspell_list.delete spell_name
              focus_list[fspell_type] = fspell_list
              magic.update(focus_cantrips: focus_list)
            else
              focus_list = magic.focus_spells
              fspell_list = focus_list[fspell_type]
              fspell_list.delete spell_name
              focus_list[fspell_type] = fspell_list
              magic.update(focus_cantrips: focus_list)
            end
          end

          client.emit_success t('pf2e.updated_ok', :char => char.name, :element => key.capitalize.gsub("_", " "))
        when "ability"
          # Expected structure of self.value: <ability name> <new score>

          abilname = self.value[0].upcase
          score = self.value[1].to_i

          abil_obj = char.abilities.select { |a| a.name_upcase == abilname }.first

          if !abil_obj
            client.emit_failure t('pf2e.bad_ability', :char => char.name)
            return
          end

          # Score validation for the admin command only makes sure it's a positive integer.
          # Game admins are responsible for ensuring that the new value is reasonable. :)
          if !(score > 0)
            client.emit_failure t('pf2e.bad_value', :item => 'ability score')
            return
          end

          abil_obj.update(base_val: score)

          client.emit_success t('pf2e.updated_ok', :char => char.name, :element => abil_obj.name)
        when 'divine font'
          # Expected structure of self.value = 'heal' or 'harm'

          font_info = { 'divine_font' => [ self.value ]}

          PF2Magic.update_magic(char, 'charclass', font_info, client)

          client.emit_success t('pf2e.updated_ok', :char => char.name, :element => 'Divine font')
        else
          client.emit_failure t('pf2e.bad_value', :item => 'keyword')
        end

      end


    end

  end
end
