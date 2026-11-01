module AresMUSH
  module Pf2e

    # Where a character's state in an encounter comes from as they join it.
    #
    # The GM says when starting an encounter which one it carries on from, if any. A character who was in
    # that one starts as they left it; anyone else starts fresh - the neutral sheet, rested.
    module CombatantStates

      # Everything a state holds of its own, copied whole from one to another. Keyed as symbols, which is
      # how a model's defaults are keyed: a string key would lose to the default.
      def self.fields(state)
        Pf2eCombatantState::OWN.each_with_object({}) { |field, out| out[field.to_sym] = state.public_send(field) }
      end

      def self.for_join(encounter, char)
        held = of(encounter, char)

        return held if held

        from = encounter.carries_on_from ? PF2Encounter[encounter.carries_on_from] : nil
        prior = from ? of(from, char) : nil

        prior ? carried(encounter, char, prior) : fresh(encounter, char)
      end

      # The character's state in an encounter, if they have one there.
      def self.of(encounter, char)
        Pf2eCombatantState.find(:encounter_id => encounter.id, :character_id => char.id).first
      end

      # The neutral sheet, rested: every hit point, a full focus pool, the day's spells from what they have
      # prepared, the day's reagents and what an alchemist prepared of them, and nothing on them. What
      # their feats and features work out - sneak attack's dice - is worked out for them as they stand
      # here, with what they carried in.
      def self.fresh(encounter, char)
        state = Pf2eCombatantState.create(:character => char, :encounter => encounter)
        pool = Pf2emagic.focus_pool_max(char.magic)

        state.update(:focus_current => pool, :pf2_reagents => char.pf2_reagents || {})
        Pf2emagic.generate_spells_today(state) if char.magic
        Equipment.copy!(state, char)
        # Rested: anything an earlier day made is gone before this day's is made.
        %w{turn rest}.each { |lasting| Equipment.lapse!(state, lasting) }
        Pf2e.daily_refresh_reagents(state)
        Alchemy.at_rest!(state)
        Paths.apply_all!(state)

        state
      end

      # As they left another encounter, effects and all.
      def self.carried(encounter, char, prior)
        state = Pf2eCombatantState.create(fields(prior).merge(:character => char, :encounter => encounter))
        # There was time between the two to load what was shot.
        TurnState.write(state, Loading::KEY => nil)

        prior.pf2_effects.each do |effect|
          own = effect.attributes.except(:character_id, :npc_id, :state_id, :encounter_id)

          Pf2eEffect.create(own.merge(:state => state, :encounter => encounter))
        end

        Equipment.copy!(state, prior)

        state
      end

      # What a character carried on their own sheet before encounters held it, moved into an encounter
      # they are already in: their hit points, conditions, effects and what they had left to spend.
      def self.adopted(encounter, char)
        existing = of(encounter, char)

        return existing if existing

        held = {
          'pf2_conditions' => char.pf2_conditions, 'pf2_persistent' => char.pf2_persistent,
          'pf2_turn_state' => char.pf2_turn_state,
          'pf2_derived' => char.pf2_derived, 'pf2_is_dead' => char.pf2_is_dead, 'pf2_reagents' => char.pf2_reagents
        }
        held.merge!(StateHP::FIELDS.to_h { |field| [ field, char.hp.public_send(field) ] }) if char.hp

        if char.magic
          held.merge!('spells_today' => char.magic.spells_today, 'revelation_locked' => char.magic.revelation_locked,
                      'focus_current' => (char.magic.focus_pool || {})['current'].to_i)
        end

        state = Pf2eCombatantState.create(held.compact.transform_keys(&:to_sym).merge(:character => char, :encounter => encounter))

        char.pf2_effects.each { |effect| effect.update(:state => state, :character => nil, :encounter => encounter) }
        Equipment.copy!(state, char)

        state
      end

      # A character is being deleted: they leave every encounter they are in, and their state in each goes.
      def self.character_deleted(char)
        Pf2eCombatantState.find(:character_id => char.id).to_a.each do |state|
          encounter = state.encounter
          row = encounter && Combatants.rows(encounter).find { |one| one['state'].to_s == state.id.to_s }

          Combatants.leave(encounter, row['id']) if row
          state.delete
        end
      end

      # Every character's own sheet made neutral, once encounters hold what happens to them: whoever is in
      # a running encounter first takes what they carry into it. A player's roll options are theirs, and
      # a death is the story's, so both stay. Answers the characters it could not, with why: one bad row
      # does not stop the rest.
      def self.neutralize_all!(characters: Character.all, encounters: PF2Encounter.all)
        encounters.select(&:is_active).each { |encounter| Combatants.rows(encounter) }

        characters.each_with_object({}) do |char, refused|
          neutralize!(char)
        rescue StandardError => e
          refused[char.name] = e.message
        end
      end

      def self.neutralize!(char)
        char.pf2_effects.each(&:delete)
        char.update(:pf2_conditions => {}, :pf2_persistent => [], :pf2_turn_state => {}, :pf2_derived => {})
        char.hp&.update(:damage => 0, :temp_hp => 0, :temp_hp_source => nil, :temp_max => 0, :temp_current => 0)

        return unless char.magic

        char.magic.update(:spells_today => {}, :revelation_locked => false,
                          :focus_pool => { 'current' => Pf2emagic.focus_pool_max(char.magic) })
      end
    end
  end
end
