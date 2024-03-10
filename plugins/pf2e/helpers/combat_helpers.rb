module AresMUSH
  module Pf2e

    def self.is_valid_init_stat?(stat)

      abilities = [ 'Strength', 'Dexterity', 'Constitution', 'Intelligence', 'Wisdom', 'Charisma' ]
      skills = Global.read_config('pf2e_skills').keys
      combat_stats = ['Perception']

      valid_init_stat = abilities + skills + combat_stats

      # Is there a unique match? Error if no match or multiple matches

      usable_init_stat = valid_init_stat.select { |s| s.match? stat }

      return false unless usable_init_stat.size == 1
      return true
    end

    def self.can_join_encounter(char, encounter)
      scene = encounter.scene
      active_encounter = PF2Encounter.in_active_encounter? char

      return "In another encounter" if active_encounter

      is_participant = scene.participants.include? char

      return "Not a scene participant" unless is_participant

      encounter_is_active = encounter.is_active

      return "Not an active encounter" unless encounter_is_active
      return nil
    end

    def self.can_damage_pc?(char, target_list, encounter=nil)

      return true if char.has_permission?('kill_pc')

      encounter = PF2Encounter[encounter]

      return false unless encounter

      is_organizer = encounter.organizer == char.name
      participants = encounter.participants.collect { |p| p[1] }
      targets_in_encounter = target_list.all? { |t| participants.include? t }

      is_organizer && targets_in_encounter
    end

  end
end
