module AresMUSH

  # Something a character is under for a while: Heroism's bonus for ten minutes, Rage until the end of
  # the fight, a potion's resistance for an hour.
  #
  # What it does lives in the catalogue (`pf2e_effects.yml`, imported from Foundry's effect packs) and is
  # read the same way a feat's or an item's rules are. This row is only the instance: which effect, at
  # what rank, since when, and how long it has left. It is live state rather than sheet state, so it is
  # never a grant - the ledger records what a player chose, and an effect ends on its own.
  class Pf2eEffect < Ohm::Model
    include ObjectModel

    # The catalogue entry, by its own name.
    attribute :name

    # What `@item.level` reads: the rank a spell was cast at, or an item's level. Heroism cast at 6th
    # rank is +2 rather than +1, and this is how it knows.
    attribute :level, :type => DataType::Integer, :default => 1

    # A counter the effect carries - how many stacks, how many rounds of something - where it has one.
    attribute :badge, :type => DataType::Integer

    # How long it lasts, in the catalogue's own terms: a unit, how many of it, and whether it ends as
    # a turn starts or as one ends.
    attribute :unit, :default => 'unlimited'
    attribute :duration, :type => DataType::Integer, :default => -1
    attribute :expiry

    # When it started, as an encounter tells it: the round, and whose turn it was. A duration counts
    # from that turn - "until the start of your next turn" is the caster's, not the target's.
    attribute :started_round, :type => DataType::Integer
    attribute :started_turn

    # Whether it has to be sustained, and the round it was last sustained through. It ends at the end of
    # the caster's first turn in a later round unless they sustain it again, which is the rule; its
    # duration is only the most it can last. Held as a flag of its own because an unset round reads as
    # nought.
    attribute :sustained, :type => DataType::Boolean, :default => false
    attribute :sustained_round, :type => DataType::Integer

    # Nights of rest still to come, for an effect measured in days.
    attribute :rests_left, :type => DataType::Integer

    attribute :applied_by

    # The effect that brought this one with it, where one did, so this one ends when that one does.
    attribute :granted_by

    # The aura that put it here - its emitter's id and the aura's slug - so leaving the aura, or the aura
    # ending, ends it.
    attribute :aura_of

    # The answers to what the effect asked when it was applied: which kind of energy Resist Energy
    # resists. Keyed by the choice set's flag, as Foundry keys them.
    attribute :answers, :type => DataType::Array, :default => []

    # What brought it: the item, spell or action (`item`: its slug, level, traits and tags), the
    # creature that used it (`actor`: its level and traits), and the degree of success of the check
    # that did (`outcome`, 0 to 3). Its rules read these as `parent:origin:*` and
    # `parent:context:check:outcome`, which is how a lesser antidote and a major one are the same
    # effect with different numbers. Empty when nothing said - an effect a GM added by hand.
    attribute :origin, :type => DataType::Hash, :default => {}

    # Who is under it: a character in an encounter, or a creature in one. `character` is a character
    # outside any encounter, which only an effect from before encounters held their own state can be.
    reference :character, "AresMUSH::Character"
    reference :npc, "AresMUSH::Pf2eNpc"
    reference :state, "AresMUSH::Pf2eCombatantState"
    reference :encounter, "AresMUSH::PF2Encounter"

    def holder
      self.state || self.npc || self.character
    end

    index :name
    index :aura_of
  end
end
