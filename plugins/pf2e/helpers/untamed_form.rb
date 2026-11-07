module AresMUSH
  module Pf2e

    # Untamed Form: a druid turns into a shape on their list, chosen as they cast it. The list is the shapes
    # of the polymorph spells `pf2e_untamed_shapes.yml` names, for the druid's feats and the spell's rank.
    #
    # The spell's own effect holds the clock and what the druid's feats give in any shape. The shape is an
    # effect it brings with it, which runs for as long as the spell does and ends when it ends.
    module UntamedForm

      SPELL = 'Untamed Form'.freeze
      EFFECT = 'Spell Effect: Untamed Form'.freeze
      DRAGON_FORM = 'Dragon Form'.freeze
      DRAGON_SHAPE = 'feat:dragon-shape'.freeze

      # Dragon Shape's resistance, which is asked of any shape but a dragon.
      RESISTANCES = %w{bludgeoning poison}.freeze

      # What a cast's words say about how it's spent, which aren't shapes.
      CASTING_WORDS = %w{focus focusc innate signature}.freeze

      TRADITION = 'tradition primal'.freeze

      def self.table
        Global.read_config('pf2e_untamed_shapes') || []
      end

      def self.spell?(spell)
        Acting.spell_mechanics(spell).first.to_s.casecmp?(SPELL)
      end

      # The rank the spell goes off at: a focus spell's own, however it was asked for.
      def self.rank_cast(cast, rank)
        slot = cast && cast['spell level'].to_i

        slot&.positive? ? slot : rank
      end

      # The rank a cast would reach, before anything is spent on it.
      def self.rank_to_come(holder, words)
        said = Acting.said(words, false)
        actor = Actors.of(holder)

        return [ Pf2emagic.get_auto_heighten_level(holder).to_i, 1 ].max if actor.spends_spells?

        Acting.spell_rank(holder, SPELL, Acting.spell_mechanics(SPELL).last, said, nil)
      end

      # The refusal of a cast that can't go ahead, where it's Untamed Form, or nil.
      def self.refusal(scene, spell, words, targets)
        return nil unless spell?(spell)

        holder = scene.actor.holder

        return Err.new(:own_shape_only, 'pf2e.untamed_self_only') if targets.any? { |one| one.holder != holder }

        form = BattleForms.active(holder)

        if form && !own?(form['effect'])
          return Err.new(:already_in_form, 'pf2e.untamed_in_form', 'actor' => scene.actor.label,
                                                                   'form' => ActiveEffects.bare_name(form['effect']))
        end

        chosen = choose(holder, rank_to_come(holder, words), words, :label => scene.actor.label,
                                                                    :forced => Acting.forced?(scene, words))

        chosen.err? ? chosen : nil
      end

      def self.own?(effect)
        effect.name == EFFECT || effect.granted_by == EFFECT
      end

      # The shape a cast's words name, with the resistance Dragon Shape asks for where it asks.
      def self.choose(holder, rank, words, label: holder.name, forced: false)
        said = Acting.said(words, false)['words'] - CASTING_WORDS
        dragon_shape = Effects.character_facts(holder).include?(DRAGON_SHAPE)
        resistance = dragon_shape ? said.find { |word| RESISTANCES.include?(word) } : nil
        terms = said - [ resistance ]
        shapes = available(holder, rank, :forced => forced)
        labels = shapes.map { |one| one['label'] }

        if terms.empty?
          return Err.new(:shape_needed, 'pf2e.untamed_shape_needed', 'actor' => label, 'options' => labels.join(', '))
        end

        return Err.new(:shape_ambiguous, 'pf2e.effect_ambiguous', 'effect' => terms.first, 'options' => terms.join(', ')) if terms.size > 1

        close = ActiveEffects.matching(labels, terms.first)

        if close.empty?
          return Err.new(:shape_unknown, 'pf2e.untamed_shape_unknown', 'actor' => label, 'shape' => terms.first,
                                                                       'rank' => rank, 'options' => labels.join(', '))
        end

        return Err.new(:shape_ambiguous, 'pf2e.effect_ambiguous', 'effect' => terms.first, 'options' => close.join(', ')) if close.size > 1

        shape = shapes.find { |one| one['label'] == close.first }

        if dragon_shape && !resistance && shape['spell'] != DRAGON_FORM
          return Err.new(:resistance_needed, 'pf2e.untamed_resistance_needed', 'options' => RESISTANCES.join(' or '))
        end

        Ok.new(:state => shape.merge('resistance' => resistance))
      end

      # Every shape they can take at this rank: their feats' and the rank's, or anything for a creature,
      # which has no feats and takes what its GM says.
      def self.available(holder, rank, forced: false)
        facts = Effects.character_facts(holder)
        anyone = forced || Actors.of(holder).creature?

        table.select { |row| anyone || row['feat'].nil? || facts.include?("feat:#{Domains.slug(row['feat'])}") }
             .select { |row| forced || row['rank'].to_i <= rank.to_i }
             .flat_map { |row| shapes_of(row, facts) }
             .uniq { |one| one['label'] }
      end

      # What a spell's shapes are: one effect for each, as Animal Form has; one effect that asks which, as
      # Insect Form does; or one effect that is one shape, as Pest Form is.
      def self.shapes_of(row, facts)
        name = "Spell Effect: #{row['spell']}"
        set = asked(name)

        return choices_of(row, name, set, facts) if set

        family = ActiveEffects.catalogue.keys.select { |one| one.start_with?("#{name} (") }

        return [ shape(row, name, row['spell']) ] if family.empty?

        family.map { |one| shape(row, one, one[/\(([^)]+)\)\z/, 1]) }
      end

      def self.asked(name)
        rules = Array(ActiveEffects.info(name)['rules'])

        rules.empty? ? nil : Rules.choice_sets(Effects.source(name, rules)).find { |set| Array(set['choices']).any? }
      end

      # A choice may ask for another feat, and for the spell's own effect, which is on them by the time it
      # counts: Soaring Shape's pterosaur is for one who has Ferocious Shape.
      def self.choices_of(row, name, set, facts)
        known = facts + [ "self:effect:#{Domains.slug(SPELL)}" ]

        set['choices'].select { |one| Predicate.test(one['when'], known) }
                      .map { |one| shape(row, name, one['label']).merge('answer' => one['label']) }
      end

      def self.shape(row, effect, label)
        { 'spell' => row['spell'], 'effect' => effect, 'label' => label, 'minutes' => row['minutes'] || 1 }
      end

      # The spell goes off: whatever shape they were in ends, and they take this one.
      def self.transform(scene, rank, words, out)
        holder = scene.actor.holder
        chosen = choose(holder, rank, words, :label => scene.actor.label, :forced => Acting.forced?(scene, words))

        return out['lines'] << Acting.told(chosen.key, chosen.args) if chosen.err?

        shape = chosen.state

        ActiveEffects.named_on(holder, EFFECT).each { |effect| ActiveEffects.remove(holder, effect) }

        spell = ActiveEffects.apply(holder, EFFECT, :options => [ "rank #{rank}", shape['resistance'] ].compact,
                                                    :applied_by => scene.actor.label, :encounter => scene.encounter,
                                                    :lasts => { 'unit' => 'minutes', 'value' => shape['minutes'] }).state

        ActiveEffects.apply(holder, shape['effect'], :options => [ "rank #{rank}", shape['answer'], TRADITION ].compact,
                                                     :applied_by => scene.actor.label, :encounter => scene.encounter,
                                                     :granted_by => EFFECT,
                                                     :lasts => { 'unit' => 'unlimited', 'value' => -1, 'expiry' => nil })

        out['lines'] << Acting.told('pf2e.act_untamed', :actor => scene.actor.label, :shape => shape['label'],
                                                        :lasts => ActiveEffects.remaining(spell))
      end
    end
  end
end
