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

      # The options themselves are listed in the Skills section of cg/review.
      bg_choice = to_assign['bg skill choice']
      msgs << t('pf2e.unassigned_bg_skill_choice') if bg_choice && bg_choice['selected'] == 'open'

      class_choice = to_assign['class skill choice']
      msgs << t('pf2e.unassigned_class_skill_choice') if class_choice && class_choice['selected'] == 'open'

      specialty_choice = to_assign['specialty skill choice']
      msgs << t('pf2e.unassigned_specialty_skill_choice') if specialty_choice && specialty_choice['selected'] == 'open'

      return nil if msgs.empty?
      return msgs
    end

    # Languages are handed out alongside skills, so they're counted at the same stage.
    def self.open_language_count(char)
      Array(char.pf2_to_assign['open languages']).count("open")
    end

    def self.language_messages(char)
      return nil if Pf2eSkills.open_language_count(char).zero?
      [ t('pf2e.unassigned_lang') ]
    end

    def self.cg_lock_skills(enactor, client=nil)
      # Did they do this already?
      return t('pf2e.cg_locked', :cp => 'skills') if enactor.pf2_skills_locked

      # Any errors that would stop them from locking?
      errors = Pf2eSkills.skills_messages(enactor)

      # Take the key and lock 'em up ./~
      return t('pf2e.skill_issues') if errors

      # Languages belong to this stage too, so they can't be left open either.
      open_lang = Pf2eSkills.open_language_count(enactor)
      return t('pf2e.lang_issues', :count => open_lang) if open_lang.positive?

      Pf2eSkills.apply_bg_granted_feats(enactor, client)

      enactor.update(pf2_skills_locked: true)

      Pf2e.record_checkpoint(enactor, "skills")
      return nil
    end

    def self.cg_lock_featskills(enactor)
      # Nothing reopened their skills, so there's nothing here to lock.
      return t('pf2e.nothing_to_relock') if enactor.pf2_skills_locked

      # Any errors that would stop them from locking?
      errors = Pf2eSkills.skills_messages(enactor)

      # Take the key and lock 'em up ./~
      return t('pf2e.skill_issues') if errors

      enactor.update(pf2_skills_locked: true)

      # No checkpoint to record. Skills were already committed and the feats stage doesn't have one.
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

    def self.apply_bg_granted_feats(enactor, client)
      base_info = enactor.pf2_base_info
      background = base_info ? base_info['background'] : nil
      return if background.blank?

      entries = deferred_bg_feats(background) + assigned_bg_feats(enactor, background)
      return if entries.empty?

      charclass = base_info['charclass']

      entries.each do |entry|
        parsed = Pf2e.granted_feat_entry(entry)

        unless parsed
          Global.logger.error "Background '#{background}' has a feat entry naming no feat."
          next
        end

        fname, label, source, filter = parsed
        found = Pf2e.get_feat_details(fname)

        if found.is_a?(String)
          Global.logger.error "Background '#{background}' grants '#{fname}', which did not resolve (#{found})."
          next
        end

        label = Pf2e.granted_choice_label(enactor, source) if source.present?

        msgs = Pf2e.add_granted_feat(enactor, found[0], found[1], charclass, client)
        msgs.concat(Pf2e.resolve_granted_choice(enactor, found[0], found[1], label, client, filter))

        msgs.each { |msg| client.emit_ooc msg } if client
      end
    end

    def self.deferred_bg_feats(background)
      entries = (Global.read_config('pf2e_background', background) || {})['feat']

      Array(entries).select do |entry|
        parsed = Pf2e.granted_feat_entry(entry)

        parsed && Pf2e.deferred_choice_source?(parsed[2])
      end
    end

    # The 'feat assignment' entries matching the skill they chose, if the background has any.
    def self.assigned_bg_feats(char, background)
      assignment = (Global.read_config('pf2e_background', background) || {})['feat assignment']
      return [] unless assignment.is_a?(Hash)

      selected = Pf2e.granted_choice_label(char, 'skill choice')
      return [] if selected.blank?

      pair = assignment.find { |choice, _| choice.to_s.casecmp?(selected.to_s) }
      return [] unless pair

      Array(pair[1])
    end

  end
end
