module AresMUSH
  module Pf2e

    def self.can_advance(char)
      # Are they already advancing?
      return t('pf2e.already_advancing') if char.advancing

      # Do they have enough XP?
      xp = char.pf2_xp
      return t('pf2e.not_enough_xp') unless (xp >= 1000)

      # Are they in an active encounter?
      active_encounter = PF2Encounter.in_active_encounter? char
      return t('pf2e.already_in_encounter') if active_encounter

      # Can they level?
      level = char.pf2_level
      return t('pf2e.already_max_level') if (level == Global.read_config('pf2e', 'max_level'))

      return nil
    end

    def self.assess_advancement(char,info)
      # Can the character advance?
      advfail = Pf2e.can_advance(char)
      return advfail if advfail

      # Return_msg returns a list of what they need to choose as an array.
      return_msg = []

      advancement = {}
      to_assign = {}

      info.each_pair do |key, value|
        case key
        when "choose_feat"
          # Value is an array of types to choose.
          hash = to_assign['feats'] || {}
          value.each do |feat|
            feat_list[feat] = [ "open" ]

            return_msg << t('pf2e.adv_item_feat', :value => feat)
          end
          to_assign['feats'] = hash
        when "magic_stats"
          assess_magic = PF2Magic.assess_magic_stats(char, value)

          advancement[key] = assess_magic['magic_stats']
          magic_options = assess_magic['magic_options']

          if magic_options
            # Merge is acting funky, so we brute force.
            magic_options.each_pair do |k,v|
              to_assign[k] = v
            end
            return_msg << t('pf2e.adv_item_magic', :options => magic_options.keys.sort.join(", "))
          end
        when "raise"
          # Value is an array of all the things you can choose to raise.
          # In this case, we put into to_assign what is to be raised as a key with an empty value.

          value.each do |item|
            to_assign["raise #{item}"] = "open"
            return_msg << t('pf2e.adv_item_raise', :item => item)
          end
        when "choose"
          name = value['choice_name']
          to_choose = to_assign['class option'] || {}
          to_choose[name] = value['options']

          return_msg << t('pf2e_adv_item_choose', :name => name, :options =>  options.sort.join(", "))

          to_assign['class option'] = to_choose
        else
          advancement[key] = value
        end
      end

      char.update(pf2_to_assign: to_assign)
      char.update(pf2_advancement: advancement)
      char.update(advancing: true)

      return_msg
    end

    def self.do_advancement(char, client)
      # Make sure they don't have anything left to choose.
      messages = advancement_messages(char)
      return messages.join("%r") if messages

      # Deduct the XP.
      xp = char.pf2_xp
      xp = xp - 1000
      char.pf2_xp = xp

      # Update level.
      level = char.pf2_level
      level = level + 1
      char.pf2_level = level

      # In advancement, to_process holds everything to be added to the sheet.
      # As with commit info, char.update is not used here generally because it would mean many separate writes, quickly.
      # Kinder to the database to make a whole bunch of changes and write the lot in one go at the end.
      charclass = char.pf2_base_info['charclass']

      to_process = char.pf2_advancement
      to_process.each_pair do |key, value|
        case key
        when "charclass"
          features = char.pf2_features

          value.each { |f| features << f }

          char.pf2_features = features.uniq.sort
        when "combat_stats"
          PF2eCombat.update_combat_stats(char, value)
        when "magic_stats"
          # Ignore any return, this key only includes items that do not populate to_assign.
          PF2Magic.update_magic(char, charclass, value, client)
        when "action"
          all_actions = char.pf2_actions
          actions = all_actions['actions']

          value.each do |item|
            actions << item
          end

          all_actions['actions'] = actions.uniq.sort
          char.pf2_actions = all_actions
        when "reaction"
          all_actions = char.pf2_actions
          reactions = all_actions['reactions']

          value.each do |item|
            reactions << item
          end

          all_actions['reactions'] = reactions.uniq.sort
          char.pf2_actions = all_actions
        when "raise ability"
          Pf2eAbilities.update_base_score(char,value)
        when "raise skill"
          progression = %w(untrained trained expert master legendary)

          skill = Pf2eSkills.find_skill(value, enactor)
          current_prof = skill.prof_level
          index = progression.index(current_prof)

          new_prof = progression[index + 1]

          skill.update(prof_level: new_prof)
        when "feats"
          char_feats = char.pf2_feats
          value.each_pair do |type, feat_list|

            # Account for the classification of a dedication feat.
            list = char_feats[type]
            dedication_list = char_feats['dedication']

            feat_list.each do |feat|
              if feat.match? 'Dedication'
                dedication_list << feat
              else
                list << feat
              end
            end
          end

          char.pf2_feats = char_feats
        when "charclass option"
          value.each_pair do |feature, option|
            case feature
            when "Path to Perfection"
              combat = char.combat
              saves = combat.saves
              path = saves['Path to Perfection'] || []
              value = (path.size == 2) ? 'master' : 'legendary'

              path << option

              saves[option] = value
              saves['Path to Perfection'] = path

              combat.update(saves: saves)
            else
              client.emit_ooc t('pf2e.missing_charclass_option_code', :feature => feature)
              next
            end
          end
        when "spellbook"
          magic = char.magic

          csb = magic.spellbook

          class_csb = csb[charclass]

          value.each do |spell|
            sp = Pf2emagic.get_spell_details(spell)
            spdeets = sp[1]

            level = spdeets['base_level'].to_s

            splist = class_csb[level] || []
            splist << spell
            class_csb[level] = splist
          end

          csb[charclass] = class_csb

          magic.update(spellbook: csb)
        when "repertoire"
          magic = char.magic
          repertoire = magic.repertoire

          class_rep = repertoire[charclass]

          value.each_pair do |level, spells|
            splist = (class_rep + spells).sort

            class_rep[level] = splist
          end

          repertoire[charclass] = class_rep

          magic.update(repertoire: repertoire)
        when "signature"
        when "grants"
          value.each_pair do |feat, info|
            do_feat_grants(char, info, charclass, client)
          end
        else
          client.emit_ooc "Unknown key #{key} in do_advancement. Please put in a request to code staff."
        end
      end

      advancement = char.pf2_adv_assigned || {}
      advancement[level] = to_process

      char.pf2_adv_assigned = advancement
      char.pf2_to_assign = {}
      char.pf2_advancement = {}
      char.advancing = false

      char.save
      return nil
    end

    def self.advancement_messages(char)
      msg = []

      to_assign = char.pf2_to_assign

      to_assign.each_pair do |item, info|
        case item
        when "feats"
          info.each_pair do |k,v|
            msg << t('pf2e.adv_item_feat', :value => k.gsub("charclass", "class")) if v.include? "open"
          end
        when "raise skill", "raise ability"
          type = item.delete_prefix "raise "

          # Info is blank if the item has not yet been selected.
          unless info
            msg << t('pf2e.adv_item_raise', :item => type)
          end
        when "spellbook", "repertoire"
          msg << t('pf2e.adv_item_magic', :options => item) if info.include? "open"
        when "signature"
          msg << t('pf2e.adv_item_magic', :options => item) unless info.values.first.zero?
        when "grants"
          info.keys.each do |feat|
            msg << t('pf2e.adv_item_grants', :options => feat)
          end
        end

      end

      return nil if msg.empty?
      return msg
    end

    def self.valid_class_option?(char, feature, option)
      passes_check = false

      case feature
      when "Path to Perfection"
        valid_values = %w(fortitude reflex will)

        return false unless valid_values.include? option

        saves = char.combat.saves
        path = saves['Path to Perfection'] || []

        return true if path.empty?

        if path.size == 1
          passes_check = true unless path.include? option
        else
          passes_check = true if path.include? option
        end
      end

      passes_check
    end

  end
end
