module AresMUSH
  module Pf2e

    # The Dismiss action: one action that ends an effect which says it can be dismissed, for whoever it says
    # may. `pf2e_dismissible.yml` lists them. An effect a GM added to someone counts as theirs, and the room
    # hears it was the GM's in case it was never meant to end.
    #
    # Ending an effect is hard to notice and takes everything that came with it, so the effect is always named.
    module Dismissing

      NAME = 'Dismiss'.freeze

      # A family is listed once: Animal Form covers Animal Form (Bear).
      def self.who(name)
        table = Global.read_config('pf2e_dismissible') || {}

        table[name] || table[name.sub(/\s*\([^)]*\)\z/, '')]
      end

      def self.act(scene, term, out)
        return Err.new(:no_encounter, 'pf2e.no_encounter_here') unless scene.encounter

        chosen = chosen_rows(scene, term)

        return chosen if chosen.err?

        rows = chosen.state
        added = rows.any? { |one| gm_added?(one, scene.encounter) }

        rows.each { |one| ActiveEffects.remove(one.holder, one) if Pf2eEffect[one.id] }

        out['lines'] << Telling.event(added ? 'pf2e.act_dismissed_gm' : 'pf2e.act_dismissed',
                                      :actor => scene.actor.label, :effect => ActiveEffects.bare_name(rows.first))

        Ok.new(:state => out)
      end

      def self.chosen_rows(scene, term)
        label = scene.actor.label
        groups = own_rows(scene).group_by { |one| ActiveEffects.bare_name(one) }

        if term.to_s.empty?
          return Err.new(:nothing_to_dismiss, 'pf2e.dismiss_nothing', 'actor' => label) if groups.empty?

          return Err.new(:which_to_dismiss, 'pf2e.dismiss_which', 'actor' => label, 'options' => groups.keys.sort.join(', '))
        end

        close = ActiveEffects.matching(groups.keys, term)

        return Ok.new(:state => groups[close.first]) if close.size == 1
        return Err.new(:which_to_dismiss, 'pf2e.dismiss_which', 'actor' => label, 'options' => close.sort.join(', ')) if close.any?

        why_not(scene, term)
      end

      # What the actor may dismiss. What came with another effect goes when that one does.
      def self.own_rows(scene)
        ActiveEffects.in_encounter(scene.encounter).select do |one|
          one.holder && one.granted_by.to_s.empty? && one.aura_of.to_s.empty? && allowed?(scene, one)
        end
      end

      def self.allowed?(scene, effect)
        case who(effect.name)
        when 'caster' then ActiveEffects.caster_of(effect, scene.encounter) == scene.actor.label
        when 'holder' then effect.holder == scene.actor.holder
        else false
        end
      end

      def self.gm_added?(effect, encounter)
        !effect.applied_by.to_s.empty? && !ActiveEffects.applied_by_combatant?(effect, encounter)
      end

      # What is wrong with the effect they named, which is one they may not dismiss.
      def self.why_not(scene, term)
        label = scene.actor.label
        rows = ActiveEffects.in_encounter(scene.encounter).select { |one| one.holder }
        named = ActiveEffects.matching(rows.map { |one| ActiveEffects.bare_name(one) }.uniq, term).first

        return Err.new(:not_found, 'pf2e.dismiss_not_found', 'actor' => label, 'effect' => term) unless named

        row = rows.find { |one| ActiveEffects.bare_name(one) == named && one.holder == scene.actor.holder } ||
              rows.find { |one| ActiveEffects.bare_name(one) == named }

        unless row.granted_by.to_s.empty?
          return Err.new(:came_with_another, 'pf2e.dismiss_came_with', 'effect' => named,
                                                                       'granter' => row.granted_by.sub(ActiveEffects::PREFIXES, ''))
        end

        return Err.new(:cannot_dismiss, 'pf2e.dismiss_cannot', 'effect' => named) unless who(row.name)

        Err.new(:not_theirs, 'pf2e.dismiss_not_theirs', 'actor' => label, 'effect' => named)
      end
    end
  end
end
