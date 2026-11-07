module AresMUSH
  module Pf2e

    # The Sustain action: one action that carries an effect the actor put in place through the end of their
    # next turn. One casting can leave several rows behind, one for each target and whatever an effect or
    # its aura put on others, and sustaining it sustains them all.
    #
    # An effect that does something more when sustained says so in words, and its GM runs that part.
    module Sustaining

      NAME = 'Sustain'.freeze

      def self.act(scene, term, out)
        return Err.new(:no_encounter, 'pf2e.no_encounter_here') unless scene.encounter

        chosen = chosen_rows(scene, term)

        return chosen if chosen.err?

        rows = chosen.state
        encounter = scene.encounter
        longer = rows.any? { |one| one.sustained_round.to_i < ActiveEffects.sustained_through(one, encounter) }

        covered(rows, encounter).each { |one| ActiveEffects.sustain(one, encounter) }

        out['lines'] << Telling.event(longer ? 'pf2e.act_sustained' : 'pf2e.act_sustained_again',
                                      :actor => scene.actor.label, :effect => ActiveEffects.bare_name(rows.first))

        Ok.new(:state => out)
      end

      # The rows of the one effect the actor means. Without a name, that is the only one they have.
      def self.chosen_rows(scene, term)
        label = scene.actor.label
        groups = own_rows(scene).group_by { |one| ActiveEffects.bare_name(one) }
        names = groups.keys.sort.join(', ')

        return Err.new(:nothing_to_sustain, 'pf2e.sustain_nothing', 'actor' => label) if groups.empty?

        if term.to_s.empty?
          return Ok.new(:state => groups.values.first) if groups.size == 1

          return Err.new(:which_to_sustain, 'pf2e.sustain_which', 'actor' => label, 'options' => names)
        end

        close = ActiveEffects.matching(groups.keys, term)

        return Ok.new(:state => groups[close.first]) if close.size == 1
        return Err.new(:which_to_sustain, 'pf2e.sustain_which', 'actor' => label, 'options' => close.sort.join(', ')) if close.any?

        Err.new(:not_sustaining, 'pf2e.sustain_not_found', 'actor' => label, 'effect' => term, 'options' => names)
      end

      # What the actor has to sustain themselves. What came with another effect goes along with that one.
      def self.own_rows(scene)
        sustained(scene.encounter).select do |one|
          one.granted_by.to_s.empty? && one.aura_of.to_s.empty? &&
            ActiveEffects.caster_of(one, scene.encounter) == scene.actor.label
        end
      end

      def self.covered(rows, encounter)
        names = rows.map(&:name)
        origins = rows.flat_map { |one| Auras.origins(one.holder, one.name) }

        rows + sustained(encounter).select do |one|
          !rows.include?(one) && (names.include?(one.granted_by) || origins.include?(one.aura_of))
        end
      end

      def self.sustained(encounter)
        ActiveEffects.in_encounter(encounter).select { |one| one.holder && one.sustained }
      end
    end
  end
end
