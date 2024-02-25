module AresMUSH
  module Pf2e

    def self.is_valid_init_stat?(stat)

      abilities = [ 'Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma' ]
      skills = Global.read_config('pf2e_skills').keys
      combat_stats = ['Perception']

      valid_init_stat = abilities + skills + combat_stats

      # Is there a unique match? Error if no match or multiple matches

      usable_init_stat = valid_init_stat.map { |s| s.match? init_stat }

      return false if usable_init_stat.size != 1
      return true 
    end

    def self.can_join_encounter?(char, encounter)
      scene = encounter.scene 
      active_encounter = PF2Encounter.in_active_encounter? char
      is_participant = scene.participants.include? char
      encounter_is_active = encounter.is_active

      !active_encounter & is_participant & encounter_is_active
    end

    def self.can_damage_pc?(char, target_list)
      
      encounter = PF2e.active_encounter(char)
      is_dm = enactor.has_permission?('kill_pc')

      if is_dm
        can_damage_pc = true
      elsif encounter
        is_organizer = encounter.organizer == enactor.name
        participants = encounter.participants.collect { |p| p[1] }
        targets_in_encounter = target_list.all? { |t| participants.include? t }

        can_damage_pc = is_organizer && targets_in_encounter
      else
        can_damage_pc = false
      end

      can_damage_pc
    end




  end
end