module AresMUSH
  class Player

    attribute :total_rpp, :type => DataType::Integer, :default => 0
    attribute :available_rpp, :type => DataType::Integer, :default => 0
    attribute :rpp_history, :type => DataType::Array, :default => []
    attribute :rpp_spent_by_char, :type => DataType::Hash, :default => {}
    attribute :nomlist, :type => DataType::Array, :default => []
    attribute :totalnoms, :type => DataType::Integer, :default => 0
    attribute :boons, :type => DataType::Hash, :default => {}

    ##### CLASS METHODS FOR RPP #####

    def self.award_rpp(char, award, reason)
      player = char.player

      # Is character registered?
      return t('alttracker.not_registered') unless player

      # Is the award a valid number?
      # This also thwarts the smartass who tries to award floats.
      award = award.to_i

      return t('pf2noms.not_a_number') if award.zero?

      total_rpp = player.total_rpp + award
      available_rpp = player.available_rpp + award

      # Store the time of the award as epoch time.
      time = Time.now.to_i

      award_history = player.rpp_history

      # History is displayed in reverse chrono, so prepending makes more sense

      award_history.unshift [ time, char.name, award, reason ]

      player.rpp_history = award_history
      player.total_rpp = total_rpp
      player.available_rpp = available_rpp

      player.save

      return nil
    end

    def self.spend_rpp(char, spend, reason)
      player = char.player

      # Is character registered?
      return t('alttracker.not_registered') unless player

      # Is the spend a valid number?
      spend = spend.to_i

      return t('pf2noms.not_a_number') if spend.zero?

      # Do they have enough RPP?

      available_rpp = player.available_rpp - spend

      return t('pf2noms.not_enough_rpp') if available_rpp < 0

      # Store the time of the spend as epoch time.

      time = Time.now.to_i

      spend_history = player.rpp_history

      # History is displayed in reverse chrono, so prepending makes more sense

      spend_history.unshift [ time, char.name, -spend, reason ]

      player.rpp_history = spend_history
      player.available_rpp = available_rpp

      # Track how much RPP has been spent on the character.

      char_spend_tracker = player.rpp_spent_by_char

      sptracker_for_char = char_spend_tracker[char.name]

      sptracker_for_char = 0 unless sptracker_for_char # Set to 0 if nil

      char_total_spent = sptracker_for_char + spend

      char_spend_tracker[char.name] = char_total_spent

      player.rpp_spent_by_char = char_spend_tracker

      player.save

      return nil
    end

    def self.char_has_boon?(char, boon)
      # Character must be registered to access the boon tracker.
      player = char.player
      return false unless player

      # If the character has that boon assigned to them, the boon name is the key and the character name is the value.
      boons = player.boons
      target = boon.downcase

      key = boons.has_key? target
      return false unless key

      # The value of a boon is always an array.

      value = (boons[target].include? char.name)

      value
    end

    def self.has_unassigned_boon?(char, boon)
      # This function looks to see if that boon has been granted to the player.
      # Character must be registered to access the boon tracker.
      player = char.player
      return false unless player

      # If the key exists,
      boons = player.boons
      target = boon.downcase

      key = boons.has_key? target
      return false unless key

      boons[target].include? "open"
    end


  end
end
