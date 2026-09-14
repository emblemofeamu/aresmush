module AresMUSH
  module Pf2e

    ASSURANCE_FEAT = 'Assurance'

    # Feats granting the take-10 trade on any skill rather than a single chosen one.
    UNIVERSAL_TAKE_TEN_FEATS = [ 'Assured Knowledge' ]

    # Skills the character has taken Assurance in, canonical names, in the order chosen.
    def self.assurance_skills(char)
      return [] unless has_feat?(char, ASSURANCE_FEAT)

      recorded_choices(char)
        .select { |name, _label, _level| name.to_s.casecmp?(ASSURANCE_FEAT) }
        .map { |_name, label, _level| label }
        .uniq
    end

    # The feat letting this character take 10 on this skill, or nil if none does.
    def self.take_ten_feat(char, skill_name)
      universal = UNIVERSAL_TAKE_TEN_FEATS.find { |feat| has_feat?(char, feat) }
      return universal if universal

      found = assurance_skills(char).any? { |skill| skill.to_s.casecmp?(skill_name.to_s) }

      found ? ASSURANCE_FEAT : nil
    end

    # Proficiency bonus only, which is what a take-10 result adds to the flat 10.
    def self.take_ten_bonus(char, skill_name)
      get_prof_bonus(char, Pf2eSkills.get_skill_prof(char, skill_name))
    end

    def self.match_char_skills(char, term)
      return [] if term.blank?

      search = term.to_s.strip

      exact = char.skills.to_a.find { |skill| skill.name.to_s.casecmp?(search) }
      return [ exact.name ] if exact

      char.skills.select { |skill| skill.name.to_s.upcase.include?(search.upcase) }
        .map { |skill| skill.name }
        .sort
    end

  end
end
