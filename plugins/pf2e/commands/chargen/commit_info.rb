module AresMUSH
  module Pf2e
    class PF2CommitInfoCmd
      include CommandHandler

      def check_in_chargen
        return nil if enactor.chargen_stage > 0 && !(enactor.is_approved?)
        return t('pf2e.only_in_chargen')
      end

      def handle
        if enactor.pf2_baseinfo_locked
          client.emit_failure t('pf2e.cg_options_locked')
          return
        end

        # Assemble info and validate that everything is set

        base_info = enactor.pf2_base_info
        ancestry = base_info['ancestry']
        heritage = base_info['heritage']
        background = base_info['background']
        charclass = base_info['charclass']
        subclass = base_info['specialize']
        subclass_option = base_info['specialize_info']
        faith_info = enactor.pf2_faith

        cg_errors = Pf2e.chargen_messages(ancestry, heritage, background, charclass, subclass, faith_info, subclass_option)

        if cg_errors
          client.emit_failure t('pf2e.cg_issues')
          return nil
        end

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

        if aflaw
          Pf2eAbilities.update_base_score(enactor, aflaw, -2)
        end

        # Free boosts
        boosts['free'] = %w{open open open open}

        # Charclass boosts and key ability check.
        # Check for subclass override of key ability
        # Key ability can have multiple options, if it does, slate for assignment

        key_ability = subclass_info['key_abil'] ? subclass_info['key_abil'] : charclass_info['key_abil']

        boosts['charclass'] = key_ability

        # If key ability has multiple options, I need a nested array for future checks.
        if key_ability.is_a?(Array)
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

        bg_skills = background_info["skills"] ? background_info["skills"] : []

        if bg_skills.size == 0
          client.emit_ooc t('pf2e.bg_no_options', :element => "skills")
        end

        heritage_skills = heritage_info['skills']
        class_skills = class_features_info['skills']
        subclass_skills = subclass_features_info.blank? ? [] : subclass_features_info['skills']
        subclassopt_skills = subclassopt_features_info.blank? ? [] : subclassopt_features_info['skills']

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

        bg_feats = background_info["feat"]

        if bg_feats.size > 1
          client.emit_ooc t('pf2e.multiple_options', :element=>"feat")
          to_assign['bgfeat'] = bg_feats
          bg_feats = []
        elsif bg_feats.empty?
          client.emit_ooc t('pf2e.bg_no_options', :element => "feats")
        end

        class_feats = class_features_info["feat"] ? class_features_info["feat"] : []
        subclass_feats = subclass_features_info.blank? ? [] : subclass_features_info["feat"]
        heritage_feats = heritage_info["feat"] ? heritage_info["feat"] : []
        subclass_info_feats = subclassopt_features_info.blank? ? [] : subclassopt_features_info["feat"]

        feats['general'] = bg_feats
        feats['ancestry'] = heritage_feats
        feats['charclass'] = class_feats + subclass_feats + subclass_info_feats

        to_assign['ancestry feat'] = 'unassigned'

        if class_features_info['choose_feat']&.include? 'charclass'
          to_assign['charclass feat'] = 'unassigned'
        end

        enactor.pf2_feats = feats

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

        client.emit_ooc "Initiating combat stats...
        "
        combat_stats = class_features_info['combat_stats']

        combat = Pf2eCombat.update_combat_stats(enactor,combat_stats)

        # Some classes have a choice of key ability
        # If so, set at ability commit, if not, set here

        combat.update(key_abil: key_ability) if key_ability.is_a?(String)

        # Collate and record unarmed attacks. Everyone starts with a fist.
        # A monk's fist does lethal damage, but everyone else is nonlethal with a fist.

        fist_traits = %w(agile finesse unarmed)
        fist_traits << 'nonlethal' unless charclass == 'Monk'

        unarmed_attacks = {
          'Fist' => {
              'damage' => '1d4',
              'damage_type' => 'S',
              'traits' => fist_traits.sort
          }
        }

        unarmed_attacks.merge ancestry_info['attack'] if ancestry_info['attack']
        unarmed_attacks.merge heritage_info['attack'] if heritage_info['attack']
        unarmed_attacks.merge subclass_option_info['attack'] if subclass_option_info

        combat.update(unarmed_attacks: unarmed_attacks.compact)

        # Starting Magic

        # Most characters will be casters in some capacity at some point in their development,
        # so everyone gets one to avoid create/delete repeatedly.
        client.emit_ooc "Checking for magic..."
        magic = PF2Magic.get_create_magic_obj(enactor)

        class_mstats = class_features_info['magic_stats'] ? class_features_info['magic_stats'] : {}
        subclass_mstats = subclass_features_info.blank? ? {} : subclass_features_info['magic_stats']

        magic_stats = class_mstats.merge(subclass_mstats)

        if magic_stats.empty?
          client.emit_ooc "This combination of options does not have magical abilities to set up. Continuing."
        else
          PF2Magic.update_magic(enactor, charclass, magic_stats, client)
          client.emit_ooc "Setting up magic..."
        end

        magic.save

        # Languages
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

        s_actions = subclass_features_info.blank? ? {} : subclass_features_info['action']
        s_reactions = subclass_features_info.blank? ? {} : subclass_features_info['reaction']

        actions = h_actions + b_actions + c_actions + s_actions.uniq.sort
        reactions = h_reactions + b_reactions + c_reactions + s_reactions.uniq.sort

        char_actions['actions'] = actions
        char_actions['reactions'] = reactions

        enactor.pf2_actions = char_actions

        # Check for and handle weird edge cases
        Pf2e.cg_edge_cases(enactor, charclass, heritage, background)

        # Put everything together, lock it, and save to database
        enactor.pf2_to_assign = to_assign
        # pf2_cg_assigned is the reset point for skills, feats, etc
        enactor.pf2_cg_assigned = to_assign
        enactor.pf2_boosts_working = boosts
        # pf2_boosts is the reset point for boosts
        enactor.pf2_boosts = boosts
        enactor.pf2_baseinfo_locked = true

        enactor.save

        client.emit_success t('pf2e.chargen_committed')
      end
    end
  end
end
