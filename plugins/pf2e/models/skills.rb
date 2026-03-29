module AresMUSH
  class Pf2eSkills < Ohm::Model
    include ObjectModel
    include FindByName

    attribute :name
    attribute :name_upcase
    attribute :prof_level
    attribute :cg_skill, :type => DataType::Boolean
    attribute :checkpoint, :type=> DataType::Hash, :default => {}

    index :name_upcase

    before_save :set_upcase_name

    def set_upcase_name
      self.name_upcase = self.name.upcase
    end

    reference :character, "AresMUSH::Character"

    ##### CLASS METHODS #####

    def self.get_linked_attr(name)
      skill = Global.read_config('pf2e_skills', name)
      linked_attr = skill['key_abil']

      linked_attr
    end

    def self.find_skill(name, char)
      skill = char.skills.select { |s| s.name_upcase == name.upcase }.first

      skill
    end

    def self.get_skill_bonus(char, name)
      skill = find_skill(name, char)
      linked_attr = get_linked_attr(name)
      abonus = Pf2eAbilities.abilmod(
        Pf2eAbilities.get_score(char, linked_attr)
      )
      pbonus = skill ? Pf2e.get_prof_bonus(char, skill.prof_level) : 0

      abonus + pbonus
    end

    def self.get_skill_prof(char, name)
      skill = find_skill(name, char)
      prof = skill ? skill.prof_level : "untrained"

      prof
    end

    def self.create_skill_for_char(name, char)
      Pf2eSkills.create(name: name, prof_level: 'untrained', character: char)
    end

    def self.update_skill_for_char(name, char, prof, cg_skill=false)
      skill = find_skill(name, char)

      return nil if !skill

      skill.update(prof_level: prof)
      skill.update(cg_skill: true) if cg_skill
    end

    def self.skills_messages(char)
      msgs = []
      to_assign = char.pf2_to_assign

      choose_open_skill = Array(to_assign['open skills']).include?("open")

      msgs << t('pf2e.unassigned_openskill') if choose_open_skill

      bg_choice = to_assign['bg skill choice']
      if bg_choice && bg_choice['selected'] == 'open'
        bg_options = Array(bg_choice['options']).compact
        if bg_options.size > 5
          msgs << t('pf2e.unassigned_bg_skill_choice_many')
        else
          msgs << t('pf2e.unassigned_bg_skill_choice', :options => bg_options.sort.join(", "))
        end
      end

      class_choice = to_assign['class skill choice']
      if class_choice && class_choice['selected'] == 'open'
        msgs << t('pf2e.unassigned_class_skill_choice', :options => class_choice['options'].sort.join(", "))
      end

      return nil if msgs.empty?
      return msgs
    end

    def self.cg_lock_skills(enactor, client=nil)
      # Did they do this already?
      return t('pf2e.cg_locked', :cp => 'skills') if enactor.pf2_skills_locked

      # Any errors that would stop them from locking?
      errors = Pf2eSkills.skills_messages(enactor)

      # Take the key and lock 'em up ./~
      return t('pf2e.skill_issues') if errors

      Pf2eSkills.apply_bg_skill_feat_assignment(enactor, client)

      enactor.update(pf2_skills_locked: true)

      Pf2e.record_checkpoint(enactor, "skills")
      return nil
    end

    def self.cg_lock_featskills(enactor)
      # Did they do this already?
      return t('pf2e.cg_locked', :cp => 'featskills') if enactor.pf2_skills_locked

      # Any errors that would stop them from locking?
      errors = Pf2eSkills.skills_messages(enactor)

      # Take the key and lock 'em up ./~
      return t('pf2e.skill_issues') if errors

      enactor.update(pf2_skills_locked: true)

      # No need to record a checkpoint due to feats being the last step.
      # Pf2e.record_checkpoint(enactor, "skills")
      return nil
    end

    def self.get_next_prof(char, value)
      progression = Global.read_config('pf2e', 'prof_progression')

      skill = Pf2eSkills.find_skill(value, char)
      current_prof = skill.prof_level
      index = progression.index(current_prof)

      progression[index + 1]
    end

    def self.min_level_for_prof(prof)
      progression = Global.read_config('pf2e', 'prof_progression')
      min_levels = Global.read_config('pf2e', 'min_level_for_prof')

      # Helper will return nil if invalid prof is given.
      index = progression.index prof
      return index unless index

      min_levels[index]
    end

    def self.factory_default(char)
      char.skills.each do |skill|
        skill.update(prof_level: 'untrained')
        skill.update(cg_skill: false)
      end
    end

    def self.apply_bg_skill_feat_assignment(enactor, client)
      base_info = enactor.pf2_base_info
      background = base_info ? base_info['background'] : nil
      return if background.blank?

      background_info = Global.read_config('pf2e_background', background) || {}
      assignment = background_info['feat assignment']
      return if assignment.blank?

      to_assign = enactor.pf2_to_assign
      bg_choice = to_assign['bg skill choice'] || {}
      selected = bg_choice['selected']
      return if selected.blank? || selected == 'open'

      choice_pair = assignment.find { |choice, _| choice.to_s.casecmp?(selected.to_s) }
      return unless choice_pair

      choice_assignment = choice_pair[1] || {}
      feats = enactor.pf2_feats
      charclass = base_info['charclass']

      choice_assignment.each_pair do |type_key, feat_list|
        feat_type = Pf2eSkills.normalize_feat_type(type_key)
        next unless feat_type

        list = feats[feat_type] || []
        Array(feat_list).each do |feat_name|
          feat_info = Pf2e.get_feat_details(feat_name)
          next if feat_info.is_a?(String)

          canonical_name = feat_info[0]
          next if list.any? { |f| f.to_s.casecmp?(canonical_name.to_s) }

          list << canonical_name

          if client
            details = feat_info[1]
            if details && details['grants']
              Pf2e.do_feat_grants(enactor, details['grants'], charclass, client)
            end
          end
        end

        feats[feat_type] = list
      end

      enactor.update(pf2_feats: feats)
    end

    def self.normalize_feat_type(type_key)
      return nil if type_key.blank?

      key = type_key.to_s.strip.downcase.gsub(/\s+/, '_')
      key = key.sub(/_feat\z/, '')

      allowed = %w(ancestry charclass general skill)
      return key if allowed.include?(key)

      nil
    end

  end
end
