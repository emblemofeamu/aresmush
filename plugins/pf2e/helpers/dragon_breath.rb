module AresMUSH
  module Pf2e

    # A dragon's breath in the hands of a character.
    #
    # Dragon Form gives an action while the form lasts: the chosen dragon's shape, damage and save against
    # the caster's spell DC, and 1d4 rounds before it can be used again. Dragon's Rage Breath is a Dragon
    # Instinct barbarian's feat: a level's worth of d6s of their dragon's damage in a cone, against their
    # class DC, while raging. Each is an area, so its damage is rolled once and each target saves.
    #
    # The Dragon Breath focus spell is cast like any other spell, and takes its damage type from here.
    module DragonBreath

      FORM_ACTION = 'Dragon Breath (Dragon Form)'.freeze
      RAGE_ACTION = "Dragon's Rage Breath".freeze
      SPELL = 'Dragon Breath'.freeze

      FORM = 'Spell Effect: Dragon Form'.freeze
      RAGE = 'Effect: Rage'.freeze
      INSTINCT = 'Dragon Instinct'.freeze

      # The round Dragon Form's breath is ready again.
      RECHARGE = 'dragon_breath_ready'.freeze

      AREAS = { 'cone' => '30-foot cone', 'line' => '100-foot line' }.freeze

      def self.action?(name)
        [ FORM_ACTION, RAGE_ACTION ].include?(name)
      end

      # Dragon Form's breath is theirs for as long as the form is.
      def self.grants?(holder, name)
        name == FORM_ACTION && !form_effect(holder).nil?
      end

      def self.form_effect(holder)
        ActiveEffects.named_on(holder, FORM).first
      end

      def self.act(scene, name, targets, said, out)
        return Err.new(:no_encounter, 'pf2e.no_encounter_here') unless scene.encounter
        return Err.new(:needs_targets, 'pf2e.breath_needs_targets', 'action' => name) if targets.empty?

        holder = scene.actor.holder
        found = name == FORM_ACTION ? from_form(holder) : from_rage(holder)

        return found if found.err?

        breath = found.state
        dc = (scene.permitted && said['dc']) || breath['dc'] || said['dc']

        return Err.new(:needs_dc, 'pf2e.breath_needs_dc', 'action' => name) unless dc

        if name == FORM_ACTION
          waiting = recharging(scene)

          return waiting if waiting
        end

        out['lines'] << Telling.event('pf2e.act_breath', :actor => scene.actor.label, :action => name,
                                                         :cost => Actions.cost(name), :formula => breath['formula'],
                                                         :type => breath['type'], :area => breath['area'],
                                                         :save => breath['save'], :dc => dc)

        rolled(scene, name, targets, breath, dc, out)
        recharge(scene, out) if name == FORM_ACTION

        Ok.new(:state => out)
      end

      def self.rolled(scene, name, targets, breath, dc, out)
        mechanics = { 'save' => breath['save'], 'basic' => true, 'area' => breath['area'],
                      'traits' => [ breath['tradition'], breath['type'] ].compact }
        formulas = [ [ breath['formula'], breath['type'], nil, [ 'damage' ] ] ]
        once = { 'spell' => name, 'rolled' => {}, 'at' => out['lines'].size }

        targets.each do |target|
          out['about'] = DamageAbout.of_spell(mechanics, name)

          next if Acting.immune?(mechanics['traits'], out, target, DamageAbout.spell(name))

          each = Acting::Scene.new(scene.encounter, scene.actor, target, scene.enactor, scene.permitted)

          Acting.spell_save(each, name, mechanics, dc, formulas, out, once)
        end
      end

      def self.recharging(scene)
        ready = TurnState.of(scene.actor.holder)[RECHARGE].to_i

        return nil unless scene.encounter.round.to_i < ready

        Err.new(:recharging, 'pf2e.breath_recharging', 'action' => FORM_ACTION, 'count' => ready - scene.encounter.round.to_i)
      end

      def self.recharge(scene, out)
        rounds = Array(Pf2e.roll_dice(1, 4)).flatten.first.to_i

        TurnState.write(scene.actor.holder, RECHARGE => scene.encounter.round.to_i + rounds)
        out['lines'] << Telling.event('pf2e.breath_recharge', :actor => scene.actor.label, :count => rounds)
      end

      # What the form's breath is: the chosen dragon's shape, damage and save, at the form's rank.
      def self.from_form(holder)
        effect = form_effect(holder)

        return Err.new(:not_in_form, 'pf2e.breath_not_in_form', 'actor' => holder.name) unless effect

        dragon = selected(ActiveEffects.answered(holder, effect), 'dragonForm')

        return Err.new(:no_dragon, 'pf2e.breath_no_dragon', 'actor' => holder.name) unless dragon

        Ok.new(:state => { 'formula' => effect.level.to_i >= 8 ? '14d6' : '10d6', 'type' => dragon['damageType'],
                           'save' => dragon['saveType'], 'area' => AREAS[dragon['breathShape']],
                           'tradition' => dragon['tradition'], 'dc' => spell_dc(holder, effect) })
      end

      # What a Dragon Instinct barbarian's breath is, while they rage.
      def self.from_rage(holder)
        return Err.new(:not_raging, 'pf2e.breath_not_raging', 'actor' => holder.name) unless ActiveEffects.active?(holder, RAGE)

        instinct = Effects.features(holder).find { |one| one['name'] == INSTINCT }
        dragon = instinct && selected(instinct, 'dragon')

        return Err.new(:no_dragon, 'pf2e.breath_no_dragon', 'actor' => holder.name) unless dragon

        Ok.new(:state => { 'formula' => "#{holder.pf2_level.to_i}d6", 'type' => dragon['damageType'], 'save' => 'reflex',
                           'area' => AREAS['cone'], 'tradition' => dragon['tradition'],
                           'dc' => Stat.total(holder, 'class_dc') })
      end

      def self.selected(source, flag)
        ((source['item'] || {}).dig('flags', 'system', 'rulesSelections') || {})[flag]
      end

      def self.spell_dc(holder, effect)
        stats = caster_stats(holder, effect)

        stats.is_a?(Hash) ? Acting.spell_figure(holder, 'spell_dc', stats) : nil
      end

      # Who cast it, as a spellcasting entry: the one of the tradition it was cast from, or their first.
      def self.caster_stats(holder, effect)
        magic = holder.magic

        return nil unless magic

        entries = Pf2emagic::Entries.casting(magic)
        tradition = Array(effect.answers).map { |one| one.to_s[/\Atradition\s+(\w+)\z/i, 1] }.compact.first
        entry = entries.find { |one| one['tradition'].to_s.casecmp?(tradition.to_s) } || entries.first

        entry ? Pf2emagic.get_caster_stats(holder, entry['name']) : nil
      end

      # The Dragon Breath spell, dealing the damage of the dragon their bloodline chose.
      def self.typed(holder, spell, mechanics)
        return mechanics unless spell.to_s.casecmp?(SPELL)

        picked = (holder.pf2_base_info || {})['specialize_info']
        element = picked && (Global.read_config('pf2e_subclass', 'Dragon Types', picked) || {})['element']

        return mechanics unless element

        mechanics.merge('damage' => Array(mechanics['damage']).map { |one| one.merge('type' => element) })
      end
    end
  end
end
