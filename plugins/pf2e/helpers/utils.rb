module AresMUSH
  module Pf2e

    # p can be passed to this method as nil
    def self.get_prof_bonus(char, p="untrained")
      p = "untrained" unless p
      level = (p == "untrained") ? 0 : char.pf2_level

      allow_untrained_improv = Global.read_config('pf2e', 'use_untrained_improv')

      if (p == "untrained" && allow_untrained_improv)
        if Pf2eFeats.has_feat?(char, "Untrained Improvisation")
          bonus = level < 7 ? (level / 2).floor : level
          return bonus
        end
      end

      profs = { "untrained"=>0, "trained"=>2, "expert"=>4, "master"=>6, "legendary"=>8 }
      profs[p] + level
    end

    def self.get_linked_attr_mod(char, value, type=nil)
      attr_type = type.is_a?(String) ? type.downcase : type

      case attr_type
      when 'skill'
        skill_mod = Pf2eSkills.get_linked_attr(value)
        return Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, skill_mod))
      when 'lore'
        return Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, 'Intelligence')
      when nil
        case value.downcase
        when 'fort', 'fortitude'
          return Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, 'Constitution')
        when 'ref', 'reflex', 'ranged', 'finesse'
          return Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, 'Dexterity')
        when 'will', 'perception'
          return Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, 'Wisdom')
        when 'melee'
          return Pf2eAbilities.abilmod(Pf2eAbilities.get_score char, 'Strength')
        end
      end
    end

    def self.get_keyword_value(char, word)
      downcase_word = word.downcase

      # Word could be many things - figure out which
      case downcase_word
      when 'shenanigans'
        t = Time.now
        sides = [ 2, 3, 4, 6, 8, 10, 12, 20, 30, 100, 1000 ].sample
        amount = rand(1..50)

        die_roll = Pf2e.roll_dice(amount, sides).sum
        value = t.to_i.odd? ? die_roll : -die_roll
      when 'will', 'fort', 'fortitude', 'ref', 'reflex'
        value = Pf2eCombat.get_save_bonus(char, downcase_word)

      when 'melee', 'ranged', 'unarmed', 'finesse' then 0

      when 'strength', 'dexterity', 'constitution', 'intelligence', 'wisdom', 'charisma'
        value = Pf2eAbilities.abilmod Pf2eAbilities.get_score(char, word)

      when 'str', 'dex', 'con', 'int', 'wis', 'cha'
        shortname = word.upcase
        obj = char.abilities.select { |a| a.shortname == shortname }
        return 0 if !obj
        value = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, obj.name))

      when 'sneak attack'
        sa_dice = char.combat&.sneak_attack

        return 0 if !sa_dice

        dice = sa_dice.gsub("d"," ").split
        amount = dice[0].to_i
        sides = dice[1].to_i

        value = Pf2e.roll_dice(amount, sides)

      when 'perception'
        value = Pf2eCombat.get_perception(char)
      else

        title_word = downcase_word.capitalize
        skills = Global.read_config('pf2e_skills').keys
        if skills.include?(title_word)
          value = Pf2eSkills.get_skill_bonus(char, title_word) + Pf2egear.bonus_from_item(char, title_word)
        else
          value = 0
        end

        value
      end
    end

    def self.roll_dice(amount=1, sides=20)
      amount.to_i.times.collect { |t| rand(1..sides.to_i) }
    end

    def self.character_has?(array, element)
      array.include?(element)
    end

    def self.character_has_index?(array, element)
      if array.member?(element)
        return array.index(element)
      else
        return false
      end
    end

    def self.get_level_tier(level)
      1 + (level / 4)
    end

    def self.parse_roll_string(target,list)
      aliases = target.pf2_roll_aliases
      roll_list = list.map { |word|
        aliases.has_key?(word) ?
        aliases[word].gsub("-", "+-").gsub("--","-").split("+")
        : word
      }.flatten

      dice_pattern = /([0-9]+)d[0-9]+/i
      find_dice = roll_list.select { |d| d =~ dice_pattern }

      roll_list.unshift('1d20') if find_dice.empty?

      result = []
      roll_list.map do |e|
        if e =~ dice_pattern
          dice = e.gsub("d"," ").split
          amount = dice[0].to_i > 0 ? dice[0].to_i : 1
          sides = dice[1].to_i
          result << Pf2e.roll_dice(amount, sides)
        elsif e.to_i == 0
          result << Pf2e.get_keyword_value(target, e)
        else
          result << e.to_i
        end
      end

      fmt_result = result.map do |word|
        if word.is_a? Array
          fmt_word = word.map { |w| "%xc#{w}%xn" }
          "(" + fmt_word.join(" ") + ")"
        else
          word
        end
      end

      return_hash = {}
      return_hash['list'] = roll_list
      return_hash['result'] = fmt_result
      return_hash['total'] = result.flatten.sum

      return return_hash
    end

    def self.get_degree(list,result,total,dc)
      degrees = [ "(%xrCRITICAL FAILURE%xn)",
        "(%xh%xyFAILURE%xn)",
        "(%xgSUCCESS!%xn)",
        "(%xh%xmCRITICAL SUCCESS!%xn)"
      ]
      if total - dc >= 10
        scase = 3
      elsif total >= dc
        scase = 2
      elsif total - dc <= -10
        scase = 0
      else
        scase = 1
      end

      #### Success modifiers happen only if the first item in the list is a 1d20.

      succ_mod = 0
      whirldice = ""

      if list[0] == '1d20'

        int_result = result[0].delete_prefix("(%xc").delete_suffix("%xn)").to_i
        if int_result == 20
          succ_mod = 1
        elsif int_result == 1
          succ_mod = -1
          whirldice = t('pf2e.whirldice')
        end
      end

      success_case = (scase + succ_mod).clamp(0,3)
      degrees[success_case] + whirldice
    end

    def self.pretty_string(string)
      string.split.map { |w| w.capitalize }.join(" ")
    end

    def self.award_xp(target, amount)
      xp = target.pf2_xp + amount
      target.update(pf2_xp: xp)
    end

    def self.record_history(char, record_type, awarded_by, amount, reason)
      new_record = {
        'from' => awarded_by,
        'amount' => amount,
        'reason' => reason.slice(0,60)
      }
      timestamp = Time.now

      full_list = char.pf2_award_history
      type_list = full_list[record_type]
      type_list[timestamp] = new_record
      full_list[record_type] = type_list
      char.update(pf2_award_history: full_list)
    end

    def self.record_xp_history(char, awarded_by, amount, reason)
      timestamp = Time.now.to_i

      xp_history = char.pf2_xp_history

      # History is displayed in reverse chrono, so prepending makes more sense
      xp_history.unshift [ timestamp, awarded_by, amount, reason ]

      char.update(pf2_xp_history: xp_history)
    end

    def self.is_proficient?(char, category, name)

      return true if char.is_admin?

      case category
      when "weapons"
        prof = Pf2eCombat.get_weapon_prof(char, name)
      when "armor"
        prof = Pf2eCombat.get_armor_prof(char, name)
      else
        prof = 'untrained'
      end

      return false if !prof || prof == 'untrained'
      return true
    end

    def self.select_best_prof(array)
      profs = %w{untrained trained expert master legendary}

      array.sort_by{ |a,b| profs.index(a) <=> profs.index(b) }.pop
    end

    def self.cannot_respec(char)
      msg = []

      # Characters cannot respec if they're in any scenes still in progress, because they will be unapproved
      # in the process of the respec.
      open_scenes = Scene.all.select { |s| s.completed && (s.participants.include?(char) || s.owner == char) }

      msg << t('pf2e.respec_refused_scenes') unless open_scenes.empty?

      # Only approved characters can respec, otherwise just reset.

      msg << t('pf2e.respec_refused_approval') unless char.is_approved?

      return msg unless msg.empty?
      return nil
    end

    def self.respec_character(char)
      # A respec does not delete XP, level, or character wealth, but does clear all stats and inventory.

      if char.is_approved?
        char.update(approval_job: nil)
        char.update(chargen_locked: false)
        Roles.remove_role(char, "approved")
      end

      # I am aware of Faraday's suggestion for using .update, but when I am changing many things at once,
      # I may as well do one DB write instead of two dozen.

      char.chargen_stage = 0
      char.pf2_baseinfo_locked = false
      char.pf2_abilities_locked = false
      char.pf2_reset = false

      char.pf2_base_info = { 'ancestry'=>"", 'heritage'=>"", 'background'=>"", 'charclass'=>"", "specialize"=>"" }
      char.pf2_conditions = {}
      char.pf2_features = []
      char.pf2_traits = []
      char.pf2_feats = { "ancestry"=>[], "charclass"=>[], "skill"=>[], "general"=>[] }
      char.pf2_faith = { 'deity'=>"", 'alignment'=>"" }
      char.pf2_special = []
      char.pf2_boosts_working = { 'free'=>[], 'ancestry'=>[], 'background'=>[], 'charclass'=>[] }
      char.pf2_boosts = {}
      char.pf2_to_assign = {}
      char.pf2_lang = []
      char.pf2_movement = {}
      char.pf2_reagents = {}
      char.pf2_formula_book = {}
      char.advancing = nil
      char.pf2_last_refresh = nil
      char.pf2_cg_assigned = {}
      char.pf2_adv_assigned = {}
      char.pf2_size = ""
      char.pf2_roll_aliases = {}
      char.pf2_actions = {}
      char.pf2_is_dead = nil
      char.pf2_known_for = []
      char.pf2_alloc_reagents = 0

      # Reset money and gear if that plugin is installed. Respec preserves money.
      Pf2egear.reset_gear(char, true) if AresMUSH.const_defined?("Pf2egear")

      # All characters have all objects except magic, so to minimize DB bloat, reuse existing objects.
      Pf2eAbilities.factory_default(char)
      Pf2eSkills.factory_default(char)
      Pf2eHP.factory_default(char)
      Pf2eCombat.factory_default(char)
      PF2Magic.factory_default(char)

      char.save
    end

    def self.reset_character(char)
      # This undoes all approvals and takes the character back to the very beginning.

      if char.is_approved?
        char.update(approval_job: nil)
        char.update(chargen_locked: false)
        Roles.remove_role(char, "approved")
      end

      char.chargen_stage = 0
      char.pf2_baseinfo_locked = false
      char.pf2_abilities_locked = false
      char.pf2_skills_locked = false
      char.pf2_checkpoint = 'start'
      char.pf2_reset = false

      char.pf2_base_info = { 'ancestry'=>"", 'heritage'=>"", 'background'=>"", 'charclass'=>"", "specialize"=>"" }
      char.pf2_xp = 0
      char.pf2_conditions = {}
      char.pf2_features = []
      char.pf2_traits = []
      char.pf2_feats = { "ancestry"=>[], "charclass"=>[], "skill"=>[], "general"=>[] }
      char.pf2_faith = { 'deity'=>"", 'alignment'=>"" }
      char.pf2_special = []
      char.pf2_boosts_working = { 'free'=>[], 'ancestry'=>[], 'background'=>[], 'charclass'=>[] }
      char.pf2_boosts = {}
      char.pf2_to_assign = {}
      char.pf2_lang = []
      char.pf2_movement = {}
      char.pf2_reagents = {}
      char.pf2_formula_book = {}
      char.advancing = nil
      char.pf2_last_refresh = nil
      char.pf2_level = 1
      char.pf2_viewsheet = {}
      char.pf2_cg_assigned = {}
      char.pf2_adv_assigned = {}
      char.pf2_size = ""
      char.pf2_roll_aliases = {}
      char.pf2_actions = {}
      char.pf2_xp_history = []
      char.pf2_is_dead = nil
      char.pf2_known_for = []
      char.pf2_alloc_reagents = 0

      # Reset money and gear if that plugin is installed.
      Pf2egear.reset_gear(char) if AresMUSH.const_defined?("Pf2egear")

      # All characters have all objects except magic, so to minimize DB bloat, reuse existing objects.
      Pf2eAbilities.factory_default(char)
      Pf2eSkills.factory_default(char)
      Pf2eHP.factory_default(char)
      Pf2eCombat.factory_default(char)
      PF2Magic.factory_default(char)

      char.save
    end

    def self.get_character(name, enactor)
      # Because Faraday can go fuck a cactus if she thinks I'm typing this ten thousand times.

      return enactor unless name

      result = ClassTargetFinder.find(name, Character, enactor)
      if (result.found?)
        return result.target
      else
        return nil
      end
    end

    def self.update_reagents(char, info, cleanup=false)

      reagents = char.pf2_reagents

      if cleanup
        info.each_pair do |k,v|
          reagents.delete[k]
        end
      else
        info.each_pair do |k,v|
          reagents[k] = v
        end
      end

      char.update(pf2_reagents: reagents)

    end

    def self.treat_as_charclass?(char, charclass, dedication_gets=true)
      # Determine whether a class' features apply to this character.
      charclass = charclass.upcase

      return true if char.pf2_base_info['charclass'].upcase == charclass

      if dedication_gets
        dedication_feat = charclass + "Dedication"

        return true if Pf2e.has_feat?(char, dedication_feat)
      end

      return false
    end

    def self.easter_scrub(ary)
      # This is used to scrub Easter egg options out of any array.
      # Use for option output to players.

      return ary unless ary.is_a? Array

      scrubs = Global.read_config('pf2e', 'hidden_options') || []

      ary - scrubs
    end

  end
end
