module AresMUSH
  module Pf2e

    # p can be passed to this method as nil
    #
    # Whether a list of traits holds one, however it was written.
    #
    # The weapon catalogue writes them Title Case with parenthesised parameters (`Deadly (d8)`),
    # chargen writes an unarmed attack's lowercase, and a few are slugs. A reader that compares with
    # `include?` answers no for half the game's data.
    def self.has_trait?(traits, wanted)
      Array(traits).any? { |trait| trait.to_s.strip.casecmp?(wanted.to_s.strip) }
    end

    def self.get_prof_bonus(char, p="untrained")
      p = "untrained" unless p
      level = (p == "untrained") ? 0 : char.pf2_level

      if p == "untrained" && Pf2e.has_feat?(char, "Untrained Improvisation")
        return untrained_improv_bonus(char.pf2_level)
      end

      profs = { "untrained"=>0, "trained"=>2, "expert"=>4, "master"=>6, "legendary"=>8 }
      profs[p] + level
    end

    # Untrained Improvisation: level - 2, improving to level - 1 at 5th and full level at 7th.
    def self.untrained_improv_bonus(level)
      return level if level >= 7

      step = level >= 5 ? 1 : 2

      [ level - step, 0 ].max
    end

    # The six abilities, and every word that names one: the full name and the three-letter
    # shorthand players actually type.
    ABILITIES = %w(Strength Dexterity Constitution Intelligence Wisdom Charisma).freeze

    ABILITY_BY_WORD = ABILITIES.each_with_object({}) { |ability, words|
      words[ability.downcase] = ability
      words[ability[0, 3].downcase] = ability
    }.freeze

    # The ability a save, an attack kind or perception is rolled off. PF2e fixes all of these, so
    # this is a register to look things up in.
    LINKED_ABILITY = {
      'fort' => 'Constitution', 'fortitude' => 'Constitution',
      'ref' => 'Dexterity', 'reflex' => 'Dexterity', 'ranged' => 'Dexterity', 'finesse' => 'Dexterity',
      'will' => 'Wisdom', 'perception' => 'Wisdom',
      'melee' => 'Strength'
    }.freeze

    SAVES = %w(will fort fortitude ref reflex).freeze

    # An attack keyword names which ability the attack uses. The bonus comes from the weapon, so the
    # keyword itself adds nothing to a roll.
    ATTACK_KINDS = %w(melee ranged unarmed finesse).freeze

    # The ability modifier behind a value, for a roll that looks one up instead of adding it. `type`
    # says how to read `value`: a skill's linked ability, a lore's Intelligence, or, when no type is
    # given, a save or attack keyword.
    def self.get_linked_attr_mod(char, value, type=nil)
      ability = case type.to_s.downcase
                when 'skill' then Pf2eSkills.get_linked_attr(value)
                when 'lore'  then 'Intelligence'
                when ''      then LINKED_ABILITY[value.to_s.downcase]
                end

      return nil unless ability

      ability_mod(char, ability)
    end

    def self.ability_mod(char, ability)
      Pf2eAbilities.abilmod(Pf2eAbilities.get_score(char, ability))
    end

    # A word in a roll string, and how to turn it into a number.
    #
    # Rows are tried in order and the last one matches anything, so a word this does not recognise
    # is looked up as a skill and otherwise contributes nothing. Adding a keyword is adding a row.
    #
    # A row may return an array of individual dice, which `parse_roll_string` shows in brackets
    # and flattens into the total. Sneak attack does; that is deliberate.
    KEYWORDS = [
      {
        'name' => 'shenanigans',
        'match' => lambda { |word| word == 'shenanigans' },
        'value' => lambda { |_char, _word| Pf2e.shenanigans }
      },
      {
        'name' => 'save',
        'match' => lambda { |word| SAVES.include?(word) },
        'value' => lambda { |char, word| Pf2eCombat.get_save_bonus(char, word) }
      },
      {
        'name' => 'perception',
        'match' => lambda { |word| word == 'perception' },
        'value' => lambda { |char, _word| Pf2eCombat.get_perception(char) }
      },
      {
        'name' => 'attack',
        'match' => lambda { |word| ATTACK_KINDS.include?(word) },
        'value' => lambda { |_char, _word| 0 }
      },
      {
        'name' => 'ability',
        'match' => lambda { |word| ABILITY_BY_WORD.key?(word) },
        'value' => lambda { |char, word| Pf2e.ability_mod(char, ABILITY_BY_WORD[word]) }
      },
      {
        'name' => 'sneak attack',
        'match' => lambda { |word| word == 'sneak attack' },
        'value' => lambda { |char, _word| Pf2e.sneak_attack_dice(char) }
      },
      {
        'name' => 'skill',
        'match' => lambda { |_word| true },
        'value' => lambda { |char, word| Pf2e.skill_keyword_bonus(char, word) }
      }
    ].freeze

    def self.get_keyword_value(char, word)
      downcased = word.to_s.downcase
      keyword = KEYWORDS.find { |k| k['match'].call(downcased) }

      keyword['value'].call(char, downcased)
    end

    # A joke roll: some number of some die, as often negative as not.
    def self.shenanigans
      sides = [ 2, 3, 4, 6, 8, 10, 12, 20, 30, 100, 1000 ].sample
      roll = Pf2e.roll_dice(rand(1..50), sides).sum

      Time.now.to_i.odd? ? roll : -roll
    end

    def self.sneak_attack_dice(char)
      dice = char.combat&.sneak_attack
      return 0 if !dice

      amount, sides = dice.gsub("d", " ").split

      Pf2e.roll_dice(amount.to_i, sides.to_i)
    end

    def self.skill_keyword_bonus(char, word)
      name = word.capitalize
      return 0 unless Global.read_config('pf2e_skills').keys.include?(name)

      Pf2eSkills.get_skill_bonus(char, name) + Pf2egear.bonus_from_item(char, name)
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
      1 + ((level - 1) / 4)
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

    # Fronts a noun phrase with 'a' or 'an' so it can be dropped into a sentence.
    ARTICLE_DETERMINERS = %w(a an the your our their his her its this that these those one any each every some no)

    def self.with_article(phrase)
      text = phrase.to_s.strip

      return text if text.empty?
      return text if ARTICLE_DETERMINERS.include?(text.split.first.to_s.downcase)
      return text if text =~ /\A[A-Z]/

      text =~ /\A[aeiou8]/i ? "an #{text}" : "a #{text}"
    end

    # The one door for moving a character's XP, in either direction. Negative spends.
    #
    # It records the transaction and moves the running total together, so there is no separate
    # history call for a caller to forget.
    def self.award_xp(target, amount, awarded_by = 'System', reason = nil, ref = nil)
      Pf2e::Audit.post(target, 'xp', amount, :by => awarded_by, :reason => reason, :ref => ref)
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

    # The highest proficiency rank in the list.
    def self.select_best_prof(array)
      profs = %w{untrained trained expert master legendary}

      array.compact.max_by { |a| profs.index(a.to_s) || -1 } || 'untrained'
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

    # A blank sheet, attribute by attribute. Both ways of starting a character over write this;
    # which of them is running decides only what is *kept*, so there is one list of what a blank
    # character looks like rather than two that drift apart.
    BLANK_SHEET = {
      :chargen_stage => 0,
      :pf2_baseinfo_locked => false,
      :pf2_abilities_locked => false,
      :pf2_skills_locked => false,
      :pf2_checkpoint => 'start',
      :pf2_reset => false,
      :pf2_base_info => { 'ancestry' => '', 'heritage' => '', 'background' => '', 'charclass' => '', 'specialize' => '' },
      :pf2_archetypeinfo => {
        'archetype1' => '', 'archetype2' => '', 'archetype3' => '', 'archetype4' => '',
        'archetype_specialty1' => '', 'archetype_specialty2' => '', 'archetype_specialty3' => '', 'archetype_specialty4' => '',
        'archetype_specialty_choice1' => '', 'archetype_specialty_choice2' => '',
        'archetype_specialty_choice3' => '', 'archetype_specialty_choice4' => ''
      },
      :pf2_conditions => {},
      :pf2_features => { 'charclass_features' => [], 'archetype_features' => [] },
      :pf2_traits => [],
      :pf2_feats => { 'ancestry' => [], 'charclass' => [], 'skill' => [], 'general' => [] },
      :pf2_faith => { 'deity' => '', 'alignment' => '', 'sanctification' => '' },
      :pf2_special => [],
      :pf2_boosts_working => { 'free' => [], 'ancestry' => [], 'background' => [], 'charclass' => [] },
      :pf2_boosts => {},
      :pf2_to_assign => {},
      :pf2_advancement => {},
      :pf2_lang => [],
      :pf2_movement => {},
      :pf2_reagents => {},
      :pf2_formula_book => {},
      :advancing => nil,
      :pf2_last_refresh => nil,
      :pf2_cg_assigned => {},
      :pf2_level_tracker => {},
      :pf2_size => '',
      :pf2_roll_aliases => {},
      :pf2_actions => {},
      :pf2_is_dead => nil,
      :pf2_known_for => [],
      :pf2_alloc_reagents => 0,
      :groups => {},
      :demographics => {}
    }.freeze

    # What a character earned rather than built. A respec keeps these; a reset does not.
    EARNED = {
      :pf2_xp => 0,
      :pf2_level => 1,
      :pf2_viewsheet => {}
    }.freeze

    # A respec: the character keeps their level, XP, money and inventory, and rebuilds everything
    # they chose. Their recorded build goes, because a ledger they are about to contradict would
    # be folded back over the blank sheet at the first write.
    def self.respec_character(char)
      blank_sheet!(char)
      Pf2egear.reset_gear(char, true) if AresMUSH.const_defined?('Pf2egear')
      char.save
    end

    # A reset: back to the very beginning, including the XP and money they were given.
    def self.reset_character(char)
      blank_sheet!(char)

      EARNED.each_pair { |attr, value| char.send("#{attr}=", value) }
      Pf2e::Audit.delete_all!(char, 'xp')

      Pf2egear.reset_gear(char) if AresMUSH.const_defined?('Pf2egear')
      char.save
    end

    def self.blank_sheet!(char)
      if char.is_approved?
        char.update(approval_job: nil)
        char.update(chargen_locked: false)
        Roles.remove_role(char, 'approved')
      end

      # The grants first. A character with grants is finalized, so until they are gone the
      # character is not back in a draft: chargen commands would write history instead of a
      # working copy, and the next materialise would restore the sheet being cleared here.
      Ledger.delete_all!(char)
      DraftJournal.clear!(char)

      BLANK_SHEET.each_pair { |attr, value| char.send("#{attr}=", value) }

      # Every character has all of these except magic, so they are reset in place rather than
      # deleted and rebuilt.
      Pf2eAbilities.factory_default(char)
      Pf2eSkills.factory_default(char)
      Pf2eHP.factory_default(char)
      Pf2eCombat.factory_default(char)
      PF2Magic.factory_default(char)
    end

    def self.get_character(name, enactor)
      # To keep from doing this repeatedly.

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

    def self.treat_as_charclass?(char, charclass)
    # Determine whether a class' features apply to this character.
      charclass = charclass.upcase
    
      return true if char.pf2_base_info['charclass'].upcase == charclass
      return false
    end

    def self.easter_scrub(ary)
      # Scrubs Easter egg options out of any array.
      # Use for option output to players.

      return ary unless ary.is_a? Array

      scrubs = Global.read_config('pf2e', 'hidden_options') || []

      ary - scrubs
    end

  end
end
