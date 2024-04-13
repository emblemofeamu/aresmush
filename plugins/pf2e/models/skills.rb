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

      choose_open_skill = to_assign['open skills'].include?("open")

      msgs << t('pf2e.unassigned_openskill') if choose_open_skill

      return nil if msgs.empty?
      return msgs
    end

    def self.cg_lock_skills(enactor)
      # Did they do this already?
      return t('pf2e.cg_locked', :cp => 'skills') if enactor.pf2_skills_locked

      # Any errors that would stop them from locking?
      errors = Pf2eSkills.skills_messages(enactor)

      # Take the key and lock 'em up ./~
      return t('pf2e.skill_issues') if errors

      enactor.update(pf2_skills_locked: true)

      Pf2e.record_checkpoint(enactor, "skills")
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

  end
end
