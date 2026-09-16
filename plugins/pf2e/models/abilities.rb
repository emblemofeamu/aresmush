module AresMUSH
  class Pf2eAbilities < Ohm::Model
    include ObjectModel
    include FindByName

    attribute :name
    attribute :name_upcase
    attribute :shortname
    attribute :base_val, :type => DataType::Integer, :default => 10
    attribute :mod_val, :default => false
    attribute :checkpoint, :type=> DataType::Hash, :default => {}

    index :name_upcase

    before_save :set_upcase_name

    def set_upcase_name
      self.name_upcase = self.name.upcase
    end

    reference :character, "AresMUSH::Character"

    ##### CLASS METHODS #####

    def self.abilmod(score=10)
      (score - 10) / 2
    end

    def self.get_score(char, ability)
      object = char.abilities.select { |a| a.name_upcase == ability.upcase }.first

      return 10 if !object

      object.mod_val ? object.mod_val : object.base_val
    end

    # A score after some number of boosts, per PF2e: a boost is worth 2, or 1 once the score has
    # reached 18.
    #
    # The rule depends only on the score being boosted, so a *count* of boosts per ability is
    # enough to derive the result - there is no ordering to preserve between abilities. That is
    # what lets the grant ledger hold boosts as counts and still reproduce the sheet.
    def self.boosted_score(base, count)
      count.to_i.clamp(0, 100).times.reduce(base.to_i) do |score, _|
        score < 18 ? score + 2 : score + 1
      end
    end

    def self.update_base_score(char,ability,mod=2)
      object = char.abilities.select { |a| a.name_upcase == ability.upcase }.first

      return nil if !object

      base = object.base_val

      if (mod.negative?)
        high_mod = -1
        mod = base <= 18 ? mod : high_mod
        new_base = base + mod
      else
        high_mod = 1
        mod = base < 18 ? mod : high_mod
        new_base = base + mod
      end

      object.update(base_val: new_base)
    end

    def self.abilities_messages(char)
      messages = []

      boosts = char.pf2_boosts_working
      a = []
      boosts.each_pair do |k,v|
        free_unassigned = v.include?("open")
        choice_not_made = v.any? { |v| v.is_a?(Array) }

        a << k if free_unassigned || choice_not_made
      end

      if !a.empty?
        messages << t('pf2e.unassigned_abilities',
          :missing => a.uniq.sort.join(", ")
        )
      end

      scores = {}
      char.abilities.each do |a|
        k = a.name
        v = a.base_val
        scores[k] = v
      end

      bad_scores = []
      scores.each do |k, v|
        bad_scores << k if v > 18
      end

      if bad_scores.count > 0
        messages << t('pf2e.ability_too_high', :score => bad_scores.join(', '))
      end

      return nil if messages.empty?
      return messages
    end

    def self.cg_lock_abilities(enactor)
      # Did they do this already?
      return t('pf2e.cg_locked', :cp => 'abilities') if enactor.pf2_abilities_locked

      # Any issues that would stop them from locking?
      errors = Pf2eAbilities.abilities_messages(enactor)

      return t('pf2e.abil_issues') if errors

      # Identify anything else they need to set.
      to_assign = enactor.pf2_to_assign

      open_skills = to_assign['open skills']
      open_languages = to_assign.has_key?('open languages') ? to_assign['open languages'] : []
      int_mod = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(enactor, 'Intelligence'))

      int_mod = 0 if int_mod < 1

      # If int_mod is positive, add that many open skills and languages

      if int_mod.positive?
        ary = []
        int_extras = ary.fill("open", nil, int_mod)

        to_assign['open skills'] = open_skills + int_extras
        to_assign['open languages'] = open_languages + int_extras

        enactor.pf2_to_assign = to_assign
      end

      # Take the key and lock 'em up ./~
      enactor.pf2_abilities_locked = true
      enactor.save

      Pf2e.record_checkpoint(enactor, "abilities")
      return nil
    end

    def self.factory_default(char)
      char.abilities.each do |abil|
        abil.update(base_val: 10)
        abil.update(mod_val: false)
      end
    end


  end
end
