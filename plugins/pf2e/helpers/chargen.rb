module AresMUSH
  module Pf2e

    def self.check_alignment(align, charclass, subclass, deity=nil)
      return nil if !(Global.read_config('pf2e', 'use_alignment'))

      all_align = Global.read_config('pf2e','allowed_alignments')
      subclass_align = Global.read_config('pf2e_specialty', subclass, 'allowed_alignments')
      class_align = Global.read_config('pf2e_class', charclass, 'allowed_alignments')
      requires_deity = Global.read_config('pf2e_class', charclass, 'use_deity')
      deity_alignments = Global.read_config('pf2e_deities', deity, 'allowed_alignments')

      calign = class_align ? class_align : all_align
      salign = subclass_align ? subclass_align : all_align

      alignments = calign & salign

      if requires_deity && (!deity || deity.blank?)
        error = t('pf2e.class_requires_deity')
      elsif requires_deity
        dalign = alignments & deity_alignments
        error = dalign.include?(align) ?
                nil :
                t('pf2e.class_deity_mismatch')
      else
        error = alignments.include?(align) ? nil : t('pf2e.class_mismatch')
      end

      return error if error
      return nil
    end

    def self.missing_base_info(ancestry, heritage, background, charclass, faith_info)
      if ancestry.blank? || heritage.blank? || background.blank? || charclass.blank?
        error = t('pf2e.missing_base_info')
      end

      return error if error
      return nil
    end

    def self.chargen_messages(ancestry, heritage, background, charclass, specialize, faith, subclass_info, to_assign=nil)
      messages = []

      missing_info = Pf2e.missing_base_info(ancestry, heritage, background, charclass, faith)
      messages << missing_info if missing_info

      bad_alignment = Pf2e.check_alignment(faith['alignment'], charclass, specialize, faith['deity'])
      messages << bad_alignment if bad_alignment

      needs_specialty = Global.read_config('pf2e', 'subclass_names').keys
      error = needs_specialty.include?(charclass) && specialize.blank?
      messages << t('pf2e.missing_subclass') if error

      needs_specialty_subinfo = !specialize.blank? && !charclass.blank? ?
        Global.read_config('pf2e_specialty', charclass, specialize) :
        {}
      missing_subclass_info = needs_specialty_subinfo.has_key?('choose') && subclass_info.blank?
      messages << t('pf2e.missing_subclass_info') if missing_subclass_info

      restricted = []

      a_rare = ancestry.blank? ? nil : Global.read_config('pf2e_ancestry', ancestry)['rare']
      b_rare = background.blank? ? nil : Global.read_config('pf2e_background', background)['rare']
      h_rare = heritage.blank? ? nil : Global.read_config('pf2e_heritage', heritage)['rare']

      restricted << "ancestry" if a_rare
      restricted << "background" if b_rare
      restricted << "heritage" if h_rare

      messages << t('pf2e.no_double_mojo') if restricted.count > 1

      return nil if messages.empty?
      return messages.join("%r")
    end

    def self.chargen_warn_player(char)
      messages = []

      feat_list = char.pf2_feats.values.flatten
      dup_feats = feat_list != feat_list.uniq

      messages << t('pf2e.duplicate_feats') if dup_feats

    end

    def self.cg_lock_base_options(enactor, client)
      # Did they do this already?
      return t('pf2e.cg_locked', :cp => 'base options') if enactor.pf2_baseinfo_locked

      # Gather information.
      base_info = enactor.pf2_base_info
      ancestry = base_info['ancestry']
      heritage = base_info['heritage']
      background = base_info['background']
      charclass = base_info['charclass']
      subclass = base_info['specialize']
      subclass_option = base_info['specialize_info']
      faith_info = enactor.pf2_faith

      cg_errors = Pf2e.chargen_messages(ancestry, heritage, background, charclass, subclass, faith_info, subclass_option)

      return t('pf2e.cg_issues') if cg_errors

      # Create abilities. Might already exist if the character reset, so check for that.

      if enactor.abilities.empty?
        client.emit_ooc "Setting up your abilities..."

        abilities = %w{Strength Dexterity Constitution Intelligence Wisdom Charisma}
        abilities.each do |a|
          Pf2eAbilities.create(name: a, character: enactor, shortname: a.slice(0,3).upcase)
        end
      else
        client.emit_ooc "Your abilities are already set up. Skipping..."
      end

      # Gather info for chargen options

      client.emit_ooc "Determining options..."

      ancestry_info = Global.read_config('pf2e_ancestry', ancestry)
      heritage_info = Global.read_config('pf2e_heritage', heritage)
      background_info = Global.read_config('pf2e_background', background)
      charclass_info = Global.read_config('pf2e_class', charclass)
      subclass_info = Global.read_config('pf2e_specialty', charclass, subclass)
      subclass_option_info = subclass_option.blank? ?
                            nil :
                            subclass_info['choose']['options'][subclass_option]
      class_features_info = charclass_info["chargen"]
      subclass_features_info = subclass_info ? subclass_info["chargen"] : {}
      subclassopt_features_info = subclass_option_info ? subclass_option_info['chargen'] : {}

      # Moved from above to here to allow subclass_features_info to assign properly
      subclass_info = {} unless subclass_info

      to_assign = enactor.pf2_to_assign

      # Ability Adjustments
      boosts = enactor.pf2_boosts_working

      # Ancestry boosts
      boosts['ancestry'] = ancestry_info['abl_boosts']

      aflaw = ancestry_info['abl_flaw']

      fixed_aboosts = ancestry_info['abl_boosts'].difference([ 'open' ])

      if !fixed_aboosts.empty?
        fixed_aboosts.each do |abil|
          Pf2eAbilities.update_base_score(enactor, abil)
        end
      end

      # Ancestry flaw, if used
      Pf2eAbilities.update_base_score(enactor, aflaw, -2) if aflaw

      # Free boosts
      boosts['free'] = %w{open open open open}

      # Charclass boosts and key ability check.
      # Check for subclass override of key ability

      key_ability = subclass_info['key_abil'] ? subclass_info['key_abil'] : charclass_info['key_abil']

      boosts['charclass'] = key_ability

      # If key ability has multiple options, I need a nested array for future checks.
      if key_ability.size > 1
        client.emit_ooc t('pf2e.multiple_options', :element=>"key ability")
        boosts['charclass'] = Array.new(1,key_ability)
      end

      # Background ability boosts
      # Number of these and their options vary.

      bg_ability = background_info['abl_boosts']

      if bg_ability.size > 1
        client.emit_ooc t('pf2e.multiple_options', :element=>"background ability option")
      elsif bg_ability.empty?
        client.emit_ooc t('pf2e.bg_no_options', :element => "ability option")
      end

      boosts['background'] = bg_ability

      # Opening Skills

      ## Create all skills with default values. Skills might already exist, check for that.

      if enactor.skills.empty?
        client.emit_ooc "Setting up your skills..."
        skill_list = Global.read_config('pf2e_skills').keys

        skill_list.each do |s|
          Pf2eSkills.create_skill_for_char(s, enactor)
        end
      else
        client.emit_ooc "Your skills are already set up. Cool. Skipping..."
      end

      ## Determine what skills come with the character's base info, and set those.

      bg_skills = background_info["skills"] || []

      if bg_skills.size == 0
        client.emit_ooc t('pf2e.bg_no_options', :element => "skills")
      end

      # Allowing for any of these to potentially be empty.

      heritage_skills = heritage_info['skills'] || []
      class_skills = class_features_info['skills'] || []
      subclass_skills = subclass_features_info.blank? ? [] : subclass_features_info['skills'] || []
      subclassopt_skills = subclassopt_features_info.blank? ? [] : subclassopt_features_info['skills'] || []

      skills = bg_skills + heritage_skills + class_skills + subclass_skills + subclassopt_skills

      # Some classes also get a skill based on their deity.
      use_deity = charclass_info.has_key?('use_deity')

      if use_deity
        deity = faith_info["deity"]
        deity_info = Global.read_config('pf2e_deities', deity)
        divine_skill = deity_info['divine_skill']
        skills << divine_skill
      end

      defined_skills = skills.difference([ "open" ])

      unique_skills = defined_skills.uniq

      if !(unique_skills.empty?)
        unique_skills.each do |s|
          Pf2eSkills.update_skill_for_char(s, enactor, 'trained', true)
        end
      end

      # Stash our open or duplicate skills for later assignment.

      extra_skills = skills.size - unique_skills.size

      ary = []
      open_skills = ary.fill("open", nil, extra_skills)

      to_assign['open skills'] = open_skills

      # Some backgrounds require you to choose a lore from a list. Stash these into to_assign.

      if background_info['lores']
        to_assign['bg_lore'] = Global.read_config('pf2e_lores', background_info['lores'])
      end

      # Feats

      client.emit_ooc "Looking for feats..."

      feats = enactor.pf2_feats

      bg_feats = background_info["feat"] || []

      if bg_feats.size > 1
        client.emit_ooc t('pf2e.multiple_options', :element=>"feat")
        to_assign['bgfeat'] = bg_feats
        bg_feats = []
      elsif bg_feats.empty?
        client.emit_ooc t('pf2e.bg_no_options', :element => "feats")
      end

      class_feats = class_features_info["feat"] ? class_features_info["feat"] : []
      subclass_feats = subclass_features_info.blank? ? [] : subclass_features_info["feat"] || []
      heritage_feats = heritage_info["feat"] ? heritage_info["feat"] : []
      subclass_info_feats = subclassopt_features_info.blank? ? [] : subclassopt_features_info["feat"] || []

      feats['general'] = bg_feats
      feats['ancestry'] = heritage_feats
      feats['charclass'] = class_feats + subclass_feats + subclass_info_feats

      to_assign['ancestry feat'] = 'open'

      if class_features_info['choose_feat']&.include? 'charclass'
        to_assign['charclass feat'] = 'open'
      end

      if class_features_info['choose_feat']&.include? 'skill'
        to_assign['skill feat'] = 'open'
      end

      if heritage_info['choose_feat']
        heritage_info['choose_feat'].each do |entry|
          type_key = entry + " feat"
          list = to_assign[type_key] || []
          list << "open"
          to_assign[type_key] = list
        end
      end

      enactor.pf2_feats = feats

      # Check for gated feats.
      # I use an array for this because there could be more than one in play at a time.

      gated_feats = []
      class_gated_feats = class_features_info["gated_feat"]
      subclass_gated_feats = subclass_features_info.blank? ? nil : subclass_features_info["gated_feat"]
      subclass_info_gated_feats = subclassopt_features_info.blank? ? nil : subclassopt_features_info["gated_feat"]

      gated_feats << class_gated_feats if class_gated_feats
      gated_feats << subclass_gated_feats if subclass_gated_feats
      gated_feats << subclass_info_gated_feats if subclass_info_gated_feats

      unless gated_feats.empty?
        client.emit_ooc t('pf2e.has_gated_feats', :options => gated_feats.sort.join(", "))

        to_assign['special feat'] = gated_feats
      end


      # Calculate and set base HP excluding CON mod
      # Final HP is calculated and set on chargen lock

      # Check for heritage override of base ancestry HP

      client.emit_ooc "Calculating HP..."

      ancestry_hp = heritage_info['ancestry_HP'] ?
                    heritage_info['ancestry_HP'] :
                    ancestry_info["HP"]

      class_hp = charclass_info["HP"]

      # This object could already exist, check for that-
      if enactor.hp
        hp = enactor.hp
        hp.update(ancestry_hp: ancestry_hp)
        hp.update(charclass_hp: class_hp)
      else
        obj = Pf2eHP.create(
          character: enactor,
          ancestry_hp: ancestry_hp,
          charclass_hp: class_hp,
        )
        enactor.hp = obj
      end

      # Senses and other specials

      client.emit_ooc "Setting up a few other items..."

      a_specials = ancestry_info["special"] ? ancestry_info["special"] : []
      h_specials = heritage_info["special"]
      b_specials = background_info["special"]

      specials = a_specials + h_specials + b_specials

      # Check for darkvision override of low-light vision
      if Pf2e.character_has?(a_specials, "Low-Light Vision") && heritage_info["change_vision"]
        specials = specials + [ "Darkvision" ] - [ "Low-Light Vision" ]
      end

      enactor.pf2_special = specials.uniq

      # Check for and set code of behavior if character has one
      edicts = []
      anathema = []

      c_edicts = charclass_info['edicts']
      c_anathema = charclass_info['anathema']

      s_edicts = subclass_info['edicts']
      s_anathema = subclass_info['anathema']

      c_edicts.each { |e| edicts << e } if c_edicts
      c_anathema.each { |a| anathema << a } if c_anathema

      s_edicts.each { |e| edicts << e } if s_edicts
      s_anathema.each { |a| anathema << a } if s_anathema

      if use_deity
        d_edicts = deity_info['edicts']
        d_anathema = deity_info['anathema']

        d_edicts.each { |e| edicts << e }
        d_anathema.each { |a| anathema << a }
      end

      faith_info['edicts'] = edicts if !edicts.empty?
      faith_info['anathema'] = anathema if !anathema.empty?

      enactor.pf2_faith = faith_info

      # Combat information - attacks, defenses, perception, class DC, saves

      client.emit_ooc "Initiating combat stats..."
      combat_stats = class_features_info['combat_stats']

      combat = Pf2eCombat.init_combat_stats(enactor,combat_stats)

      # Some classes have a choice of key ability
      # If so, set at ability commit, if not, set here

      if key_ability.size == 1
        combat.update(key_abil: key_ability.first)
        Pf2eAbilities.update_base_score(enactor, key_ability.first)
      end

      # Collate and record unarmed attacks. Everyone starts with a fist.
      # A monk's fist does 1d6, everyone else's does 1d4.

      fist_damage = Pf2e.treat_as_charclass?(enactor, "Monk") ? '1d6' : '1d4'

      unarmed_attacks = {
        'Fist' => {
            'damage' => fist_damage,
            'damage_type' => 'B',
            'traits' => %w(agile finesse nonlethal unarmed)
        }
      }

      unarmed_attacks.merge ancestry_info['attack'] if ancestry_info['attack']
      unarmed_attacks.merge heritage_info['attack'] if heritage_info['attack']
      if subclass_option_info
        unarmed_attacks.merge subclass_option_info['attack'] if subclass_option_info['attack']
      end

      combat.update(unarmed_attacks: unarmed_attacks)

      # Collate and record any special defenses or resistances.
      if heritage_info['defense']
        defenses = heritage_info['defense']
        combat.update(defense: defenses)
      end

      # Starting Magic

      # Most characters will be casters in some capacity at some point in their development,
      # so everyone gets one to avoid create/delete repeatedly.
      client.emit_ooc "Checking for magic..."
      PF2Magic.get_create_magic_obj(enactor)

      class_mstats = class_features_info['magic_stats'] ? class_features_info['magic_stats'] : {}

      # Some classes will have stuff in specialty_options. too.
      if subclass_features_info
        subclass_mstats = subclass_features_info['magic_stats']

        class_mstats = class_mstats.merge(subclass_mstats) if subclass_mstats
      end

      if subclassopt_features_info
        subclassopt_mstats = subclassopt_features_info['magic_stats']

        class_mstats = class_mstats.merge(subclassopt_mstats) if subclassopt_mstats
      end

      # Handle class specific junk.
      if charclass == 'Cleric'
        deity_mstats = deity_info['magic_stats']

        class_mstats = class_mstats.merge(deity_mstats) if deity_mstats
      elsif charclass == 'Wizard'
        # Note: The universalist wizard will overwrite the existing 'spellbook' key from the class.
        # This is planned behavior.
        wizard_school = Global.read_config('pf2e_subclass', 'wizard_school_spells', subclass_option)
        school_mstats = wizard_school&.fetch('magic_stats')

        class_mstats = class_mstats.merge(school_mstats) if school_mstats
      end

      if class_mstats.empty?
        client.emit_ooc "This combination of options does not have magical abilities to set up. Continuing."
      else
        # An unfortunate consequence of update_magic is taking to_assign out behind the toolshed and giving it
        # the Ol' Yeller. Luckily, this is a computer and not a traumatic Disney movie. We can save Ol' Yeller
        # to a temporary variable and merge it back in with the results of update_magic.
        to_assign_pre_update_magic = to_assign
        to_assign = to_assign_pre_update_magic.merge(PF2Magic.update_magic(enactor, charclass, class_mstats, client))
        client.emit_ooc "Setting up magic..."
      end

      # Heritages needs a second processing run of update_magic so that it doesn't overwrite the class.
      heritage_magic = heritage_info['magic_stats']

      if heritage_magic
        heritage_add_to_assign = PF2Magic.update_magic(enactor, charclass, heritage_magic, client)

        unless heritage_add_to_assign.empty?

        end
      end

      # Languages

      client.emit_ooc "Assessing languages...."
      languages = enactor.pf2_lang

      ancestry_info['languages'].each { |l| languages << l }

      clang = class_features_info['languages']

      clang.each { |l| languages << l } if clang

      unique_lang = languages.uniq

      enactor.pf2_lang = languages.uniq

      # PC may choose another language to replace a duplicate.

      if (languages.count != unique_lang.count)
        extra_lang = languages.count - unique_lang.count

        ary = []
        open_languages = ary.fill("open", nil, extra_lang)
        to_assign['open languages'] = open_languages
      end

      # Traits, Size, Movement, Misc Info
      traits = ancestry_info["traits"] + heritage_info["traits"] + [ charclass.downcase ]
      traits = traits.uniq.sort

      enactor.pf2_traits = traits

      movement = enactor.pf2_movement
      movement['Size'] = ancestry_info['Size']
      movement['base_speed'] = ancestry_info['Speed']

      # Some heritages offer other movement types, if so, include

      other_mtypes = heritage_info.has_key?('movement')

      if other_mtypes
        other_mtypes.each do |k,v|
          movement[k] = v
        end
      end

      enactor.pf2_movement = movement

      # Actions and reactions unique to the character
      # Should update even if the array is empty

      char_actions = enactor.pf2_actions

      h_actions = heritage_info['action']
      h_reactions = heritage_info['reaction']

      b_actions = background_info['action']
      b_reactions = background_info['reaction']

      c_actions = class_features_info['action']
      c_reactions = class_features_info['reaction']

      s_actions = subclass_features_info.blank? ? [] : subclass_features_info['action'] || []
      s_reactions = subclass_features_info.blank? ? [] : subclass_features_info['reaction'] || []

      actions = (h_actions + b_actions + c_actions + s_actions).uniq.sort
      reactions = (h_reactions + b_reactions + c_reactions + s_reactions).uniq.sort

      char_actions['actions'] = actions
      char_actions['reactions'] = reactions

      enactor.pf2_actions = char_actions

      # Put everything together, lock it, record the checkpoint, and save to database
      enactor.pf2_to_assign = to_assign
      enactor.pf2_boosts_working = boosts
      enactor.pf2_baseinfo_locked = true

      enactor.save

      Pf2e.record_checkpoint(enactor, 'info')

      return nil
    end

    def self.update_sheet(char, info)
      # This is called by the advancement code and should be called by commit info. Fix commit info to do this.

      info.each_pair do |key, value|
        case key
        when "choose_feat"
          to_assign = char.pf2_to_assign
          to_assign['feat_by_type'] = value
          char.update(pf2_to_assign: to_assign)
        when "charclass"
          features = char.pf2_features

          value.each { |f| features << f }

          char.update(pf2_features: features.uniq.sort)
        when "combat_stats"
          PF2eCombat.update_combat_stats(char, value)
        when "magic_stats"
          Pf2eMagic.update_magic_stats(char, value)
        when "skill"
        when "feat"
        when "action"
        when "reaction"
        when "familiar"
        when "animal companion"
        when "raise"
        when "choose"
        else
          client.emit_ooc "Unknown key in update_sheet: #{key}. Please raise this to code staff."
        end
      end
    end

    def self.assignments_complete?(char)
      # Assignments are incomplete if any value is "open".
      to_assign = char.pf2_to_assign

      to_assign.each_pair do |k,v|
        next unless v.include? "open"
        return false
      end

      return true
    end

    def self.record_checkpoint(char, checkpoint)
      case checkpoint
      when "info"
        to_assign = char.pf2_to_assign
        char.pf2_cg_assigned = to_assign

        boosts = char.pf2_boosts_working
        char.pf2_boosts = boosts
        char.pf2_checkpoint = 'info'
        char.save

      when "abilities" # Used by commit abilities
        to_assign = char.pf2_to_assign
        char.pf2_cg_assigned = to_assign

        boosts = char.pf2_boosts_working
        char.pf2_boosts = boosts

        char.abilities.each do |ability|
          cp_state = {}
          cp_state['base_val'] = ability.base_val
          cp_state['mod_val'] = false
          ability.update(checkpoint: cp_state)
        end

        char.pf2_checkpoint = 'abilities'

        char.save
      when "skills"
        char.skills.each do |skill|
          cp_state = {}
          cp_state['prof_level'] = skill.prof_level
          cp_state['cg_skill'] = true
          skill.update(checkpoint: cp_state)
        end

        char.update(pf2_checkpoint: 'skills')
      when "advance"
      else
        return nil
      end
    end

    def self.restore_checkpoint(char, checkpoint)

    end

  end
end
