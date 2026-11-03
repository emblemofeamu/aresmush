module AresMUSH
  module Pf2e

    # What a condition stops someone doing, by what they try. Each row is what they are under, what of
    # their actions it is about, and what comes of trying: refused outright (`key`), or risked on a flat
    # check (`flat`) that loses the action where it fails.
    #
    #   Restrained   cannot use an action with the attack or manipulate trait, except to Escape or Force
    #                Open.
    #   Immobilized  cannot use an action with the move trait.
    #   Prone        the only actions with the move trait it can use are Crawl and Stand.
    #   Raging       cannot use an action with the concentrate trait that lacks the rage trait, but Seek.
    #   Fleeing      cannot Delay or Ready.
    #   Confused     cannot Delay, Ready or use a reaction.
    #   Grabbed      an action with the manipulate trait is lost on a failed DC 5 flat check.
    #   Deafened     an action with the auditory trait is lost on a failed DC 5 flat check.
    #   Stupefied    a spell is lost on a failed flat check against 5 and the condition's value.
    #   In a form    cannot cast a spell, use a manipulate action unless the form has hands, or use a shield,
    #                which is absorbed with the rest of their gear. Each is the GM's to force (`forcible`),
    #                because the rules leave doubts about a battle form to them.
    module Restraints

      FREEING = [ 'Escape', 'Force Open' ].freeze
      WAITING = %w{Delay Ready}.freeze
      SHIELD_ACTIONS = [ 'Raise a Shield', 'Shield Block' ].freeze

      ROWS = [
        { 'condition' => 'Restrained', 'traits' => %w{attack manipulate}, 'key' => 'pf2e.act_restrained', 'unless' => FREEING },
        { 'condition' => 'Immobilized', 'traits' => %w{move}, 'key' => 'pf2e.act_immobilized' },
        { 'condition' => 'Prone', 'traits' => %w{move}, 'key' => 'pf2e.act_prone', 'unless' => %w{Crawl Stand} },
        { 'effect' => 'rage', 'traits' => %w{concentrate}, 'without' => %w{rage}, 'key' => 'pf2e.act_raging', 'unless' => %w{Seek},
          'feats' => { 'Raging Intimidation' => [ 'Demoralize', 'Scare to Death' ] } },
        { 'condition' => 'Fleeing', 'names' => WAITING, 'key' => 'pf2e.act_cannot_wait' },
        { 'condition' => 'Confused', 'names' => WAITING, 'key' => 'pf2e.act_cannot_wait' },
        { 'condition' => 'Confused', 'types' => %w{reaction}, 'key' => 'pf2e.act_cannot_react' },
        { 'condition' => 'Grabbed', 'traits' => %w{manipulate}, 'flat' => ->(_value) { 5 }, 'unless' => FREEING },
        { 'condition' => 'Deafened', 'traits' => %w{auditory}, 'flat' => ->(_value) { 5 } },
        { 'condition' => 'Stupefied', 'spell' => true, 'flat' => ->(value) { 5 + value } },
        { 'form' => true, 'spell' => true, 'key' => 'pf2e.form_no_cast', 'forcible' => true },
        { 'form' => true, 'names' => SHIELD_ACTIONS, 'key' => 'pf2e.form_no_shield', 'forcible' => true },
        { 'form' => true, 'traits' => %w{manipulate}, 'key' => 'pf2e.form_no_hands', 'forcible' => true, 'hands' => true }
      ].freeze

      # What is being tried, as the rows ask of it.
      Tried = Struct.new(:name, :traits, :type, :spell)

      def self.tried(name, traits, type: nil, spell: false)
        Tried.new(name, Array(traits).map { |trait| Domains.slug(trait) }, type.to_s, spell)
      end

      # The rows that are about someone trying this, each with what they are under that makes it so.
      def self.rows_for(holder, tried)
        held = Pf2e.held_conditions(holder)
        effects = Effects.effect_facts(holder)

        ROWS.select { |row| about?(row, tried) && under?(row, holder, held, effects) && !let?(row, holder, tried) }
            .map { |row| [ row, row['condition'] || row['effect']&.capitalize, (held[row['condition']] || {})['value'].to_i ] }
      end

      def self.under?(row, holder, held, effects)
        return BattleForms.active?(holder) if row['form']

        row['condition'] ? held.key?(row['condition']) : effects.include?("self:effect:#{row['effect']}")
      end

      def self.about?(row, tried)
        return false if (Array(row['without']) & tried.traits).any?
        return tried.spell if row['spell']
        return row['names'].include?(tried.name) if row['names']
        return row['types'].include?(tried.type) if row['types']

        (Array(row['traits']) & tried.traits).any?
      end

      # An action the row lets through: by its name, by a feat that says it may be used, or by a form that
      # has hands to use it with.
      def self.let?(row, holder, tried)
        Array(row['unless']).include?(tried.name) ||
          (row['feats'] || {}).any? { |feat, names| names.include?(tried.name) && Actions.owned?(holder, feat) } ||
          (row['hands'] && BattleForms.hands?(holder))
      end

      # What stops the action, as an error to tell whoever tried, or nothing. `forced` is the GM's word,
      # which gets past what the rules leave to them.
      def self.refusal(actor, name, traits, type: nil, spell: false, forced: false)
        row, condition = rows_for(actor.holder, tried(name, traits, :type => type, :spell => spell))
                         .find { |one, *_| one['key'] && !(forced && one['forcible']) }

        return nil unless row

        form = row['form'] ? ActiveEffects.bare_name(BattleForms.active(actor.holder)['effect']) : nil

        Err.new(:restrained, row['key'], 'actor' => actor.label, 'action' => name, 'condition' => condition, 'form' => form)
      end

      # The flat checks the action is risked on, rolled until one loses it: nothing where none is called
      # for, and otherwise whether the action is kept and the lines that say so.
      def self.risked(actor, name, traits, type: nil, spell: false)
        rows = rows_for(actor.holder, tried(name, traits, :type => type, :spell => spell)).select { |one, *_| one['flat'] }

        return nil if rows.empty?

        lines = []
        kept = rows.all? do |row, condition, value|
          flat = Resolve.flat(row['flat'].call(value))
          lines << Telling.event(flat['success'] ? 'pf2e.act_risk_kept' : 'pf2e.act_risk_lost',
                                 :actor => actor.label, :condition => condition, :action => name, :die => flat['die'], :dc => flat['dc'])

          flat['success']
        end

        { 'kept' => kept, 'lines' => lines }
      end
    end
  end
end
