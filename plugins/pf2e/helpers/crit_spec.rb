module AresMUSH
  module Pf2e

    CRIT_SPEC_PROF_ORDER = %w{untrained trained expert master legendary}

    # The ancestry weapon familiarity feats and Ciith Armaments both read "At 5th level..."
    CRIT_SPEC_ANCESTRY_LEVEL = 5

    # The critical specialization effect text for a weapon group, or nil if the group has no entry.
    def self.crit_spec_effect(group)
      key = canonical_crit_spec_group(group)

      return nil if !key

      (Global.read_config('pf2e_weapon_groups') || {})[key]['crit_spec']
    end

    def self.canonical_crit_spec_group(group)
      return nil if group.blank?

      groups = Global.read_config('pf2e_weapon_groups') || {}

      groups.keys.find { |g| g.to_s.casecmp?(group.to_s) }
    end

    def self.prof_at_least?(prof, threshold)
      have = CRIT_SPEC_PROF_ORDER.index(prof.to_s.downcase)
      need = CRIT_SPEC_PROF_ORDER.index(threshold.to_s.downcase)

      return false if have.nil? || need.nil?

      have >= need
    end

    # Does the character have this class feature?
    #
    # A feature chosen from a list is recorded with the option appended, as in "Fighter Weapon Mastery (Sword)", so both shapes have to match.
    def self.has_feature?(char, feature)
      features = (char.pf2_features || {})['charclass_features'] || []
      target = feature.to_s.upcase

      features.any? do |f|
        name = f.to_s.upcase
        name == target || name.start_with?("#{target} (")
      end
    end

    # Every attack the character gets a critical specialization effect with, as
    # { group => [ names ] }.
    #
    # Weapons are limited to what is equipped so the names line up with the weapon list csheet already prints above this section.
    def self.crit_spec_access(char)
      combat = char.combat

      return {} if !combat

      access = {}

      (combat.unarmed_attacks || {}).each_pair do |name, info|
        next if !info.is_a?(Hash)

        group = canonical_crit_spec_group(info['group'])
        next if !group
        next if !crit_spec_unarmed?(char, name, info)

        (access[group] ||= []) << name
      end

      equipped_weapon_names(char).each do |name|
        info = Global.read_config('pf2e_weapons', name)
        next if !info

        group = canonical_crit_spec_group(info['group'])
        next if !group
        next if !crit_spec_weapon?(char, name, info)

        (access[group] ||= []) << name
      end

      access.each_key { |g| access[g] = access[g].uniq.sort }

      access
    end

    # What is granting access, for the header line. Feature and feat names only, since those are proper nouns rather than prose.
    def self.crit_spec_sources(char)
      sources = []

      sources << 'Fighter Weapon Mastery' if has_feature?(char, 'Fighter Weapon Mastery')
      sources << 'Expert Strikes' if has_feature?(char, 'Expert Strikes')

      if treat_as_charclass?(char, 'Swashbuckler') && has_feature?(char, 'Weapon Expertise')
        sources << 'Weapon Expertise'
      end

      sources << 'Monastic Weaponry' if has_feat?(char, 'Monastic Weaponry') && unarmed_crit_spec?(char)

      familiarity = ancestry_familiarity_feat(char)
      sources << familiarity if familiarity && has_feat?(char, familiarity)

      sources << 'Ciith Armaments' if ciith_armament_crit_spec?(char)

      sources.uniq
    end

    # --- individual rules ---------------------------------------------------------------

    def self.crit_spec_weapon?(char, name, info)
      # Fighter Weapon Mastery: "all weapons and unarmed attacks for which you have master
      # proficiency". No group of its own, so it widens on its own as proficiency grows.
      if has_feature?(char, 'Fighter Weapon Mastery')
        return true if prof_at_least?(Pf2eCombat.get_weapon_prof(char, name), 'master')
      end

      # Swashbuckler Weapon Expertise: "all weapons for which you have expert proficiency".
      # Says weapons, not weapons and unarmed attacks, so it is not in crit_spec_unarmed?.
      if treat_as_charclass?(char, 'Swashbuckler') && has_feature?(char, 'Weapon Expertise')
        return true if prof_at_least?(Pf2eCombat.get_weapon_prof(char, name), 'expert')
      end

      # Monastic Weaponry extends whatever unarmed critical specialization the character
      # already has to monk weapons, so it is derived rather than granted outright.
      if has_feat?(char, 'Monastic Weaponry') && weapon_has_trait?(info, 'monk')
        return true if unarmed_crit_spec?(char)
      end

      # The ancestry weapon familiarity feats, from 5th level, over that ancestry's weapons.
      return true if ancestry_familiarity_crit_spec?(char, info)

      false
    end

    def self.crit_spec_unarmed?(char, name, info)
      # Fighter Weapon Mastery names unarmed attacks explicitly.
      if has_feature?(char, 'Fighter Weapon Mastery')
        return true if prof_at_least?(Pf2eCombat.get_unarmed_prof(char, name, info), 'master')
      end

      # Expert Strikes: unarmed attacks in the brawling group, with no proficiency gate.
      if has_feature?(char, 'Expert Strikes')
        return true if info['group'].to_s.casecmp?('brawling')
      end

      # Ciith Armaments, over the attacks that feat gained or improved, from 5th level.
      if ciith_armament_crit_spec?(char)
        return true if chosen_unarmed_attacks(char).keys.any? { |a| a.to_s.casecmp?(name.to_s) }
      end

      false
    end

    # Does the character have critical specialization with any unarmed attack? This is the
    # trigger for Monastic Weaponry, which grants nothing on its own.
    #
    # Safe from recursion because no rule inside crit_spec_unarmed? calls back into here.
    def self.unarmed_crit_spec?(char)
      combat = char.combat

      return false if !combat

      (combat.unarmed_attacks || {}).any? do |name, info|
        info.is_a?(Hash) && crit_spec_unarmed?(char, name, info)
      end
    end

    def self.ancestry_familiarity_crit_spec?(char, info)
      return false if char.pf2_level.to_i < CRIT_SPEC_ANCESTRY_LEVEL

      ancestry_list = info['ancestry']
      return false if !ancestry_list

      char_ancestry = char.pf2_base_info['ancestry'].to_s.downcase
      return false if !ancestry_list.include?(char_ancestry)

      feat = ancestry_familiarity_feat(char)

      feat ? has_feat?(char, feat) : false
    end

    # Built the same way get_weapon_prof builds it, so the two agree on what the feat for an
    # ancestry is called.
    def self.ancestry_familiarity_feat(char)
      char_ancestry = char.pf2_base_info['ancestry'].to_s.downcase

      return nil if char_ancestry.empty?

      %w{sildanyar khazad}.include?(char_ancestry) ?
        "#{char_ancestry}i Weapon Familiarity" :
        "#{char_ancestry} Weapon Familiarity"
    end

    def self.ciith_armament_crit_spec?(char)
      has_feat?(char, 'Ciith Armaments') && char.pf2_level.to_i >= CRIT_SPEC_ANCESTRY_LEVEL
    end

    # --- shared lookups -----------------------------------------------------------------

    # Unarmed attacks the character gained or improved through a feat choice, as
    # { attack name => feat name }.
    #
    # Read out of the feat's own config rather than hardcoded, so a future feat that grants
    # an attack through a choice works here without further changes.
    def self.chosen_unarmed_attacks(char)
      attacks = {}

      recorded_choices(char).each do |feat, label, _level|
        options = Global.read_config('pf2e_feats', feat.to_s, 'feat_choice', 'options')
        next if !options.is_a?(Hash)

        key = options.keys.find { |k| k.to_s.casecmp?(label.to_s) }
        next if !key

        granted = options[key].is_a?(Hash) ? options[key].dig('grants', 'attack') : nil
        next if !granted.is_a?(Hash)

        granted.each_key { |atk| attacks[atk] = feat }
      end

      attacks
    end

    def self.weapon_has_trait?(info, trait)
      Array(info['traits']).any? { |t| t.to_s.casecmp?(trait.to_s) }
    end

    def self.equipped_weapon_names(char)
      return [] if !AresMUSH.const_defined?("Pf2egear")

      weapons = Pf2egear.items_in_inventory(char.weapons) || []

      weapons.select { |w| w.equipped }.map { |w| w.name }
    end

  end
end
