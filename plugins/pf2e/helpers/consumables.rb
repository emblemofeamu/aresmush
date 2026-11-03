module AresMUSH
  module Pf2e

    # What a consumable does when it is used in a fight, from what the catalogue says of it
    # (`scripts/import_foundry_consumables.py`):
    #
    #   heal       the Hit Points it restores, rolled; `heal_type` vitality heals only the living and void
    #              only the undead
    #   effect     the `Effect: …` it leaves on whoever takes it
    #   bomb       it is thrown rather than taken: a Strike, with its dice, persistent and splash damage
    #
    # Answers what to tell, in the shape `Acting.report` makes, and leaves the using up to the command.
    module Consumables

      def self.info(name)
        Global.read_config('pf2e_consumables', name) || {}
      end

      def self.bomb?(name)
        info(name).key?('bomb')
      end

      # Someone takes it - the one who used it, or whoever they gave it to.
      def self.take(encounter, given_by, target, name)
        entry = info(name)
        out = Acting.report

        heal(target, name, entry, out) if entry['heal']
        effect(encounter, given_by, target, entry['effect'], out, item_origin(name, entry)) if entry['effect']

        out
      end

      def self.heal(target, name, entry, out)
        unless heals?(target.holder, entry['heal_type'])
          out['lines'] << Telling.event('pf2e.consumable_no_effect', 'item' => name, 'target' => target.label)
          return
        end

        amount = Pf2e.roll_formula(entry['heal'])
        Harm.heal(target.holder, amount)

        out['lines'] << Telling.event('pf2e.consumable_heals', 'target' => target.label, 'count' => amount,
                                                               'item' => name)
        out['gm'] << Telling.event('pf2e.act_hp_left', 'target' => target.label, 'hp' => Harm.hit_points(target.holder))
      end

      # `origin` is the item that left it, so its rules can tell which item that was: Effect: Antidote is
      # one effect for all four antidotes, and its bonus is the one the antidote taken gives.
      def self.effect(encounter, given_by, target, name, out, origin = nil)
        return unless ActiveEffects.catalogue.key?(name)

        applied = ActiveEffects.apply(target.holder, name, :applied_by => given_by, :encounter => encounter,
                                                           :origin => origin)

        return unless applied.ok?

        out['lines'] << Telling.event('pf2e.consumable_effect', 'target' => target.label, 'effect' => name)
      end

      def self.item_origin(name, entry)
        ActiveEffects.origin(item: { 'name' => name, 'type' => 'consumable', 'level' => entry['level'],
                                     'traits' => Array(entry['traits']) })
      end

      # Vitality heals the living and does nothing for the undead; void the reverse; untyped either.
      def self.heals?(holder, type)
        undead = Effects.facts(holder).include?('self:mode:undead')

        case type.to_s
        when 'vitality' then !undead
        when 'void' then undead
        else true
        end
      end

      # ------------------------------------------------------------------------------
      # Bombs

      # A bomb's damage beyond its own dice, as the rows `Damage` adds up: its persistent damage, which a
      # critical hit doubles with the rest, and its splash, which it never doubles.
      def self.bomb_rows(attack)
        return [ [], [] ] unless attack['bomb'] && attack['consumable']

        dice = []
        flat = []
        persistent = attack['persistent'].to_s

        if (rolled = persistent.match(/\A(\d+)d(\d+)\z/))
          dice << { 'source' => attack['name'], 'dice' => rolled[1].to_i, 'die' => "d#{rolled[2]}",
                    'damage_type' => attack['persistent_type'], 'category' => 'persistent', 'critical' => nil }
        elsif persistent.to_i.positive?
          flat << { 'source' => attack['name'], 'value' => persistent.to_i, 'damage_type' => attack['persistent_type'],
                    'category' => 'persistent', 'critical' => nil, 'creates' => true }
        end

        if attack['splash'].to_i.positive?
          flat << { 'source' => attack['name'], 'value' => attack['splash'].to_i, 'damage_type' => attack['damage_type'],
                    'category' => 'splash', 'critical' => false, 'creates' => true }
        end

        [ dice, flat ]
      end

      # One thrown: the holder's copy has one fewer, and none once the last is gone.
      def self.spend!(holder, id)
        item = Pf2egear::Inventory.held(holder, 'consumables').find { |one| one.id.to_s == id.to_s }

        return unless item

        item.quantity.to_i > 1 ? item.update(:quantity => item.quantity.to_i - 1) : item.delete
      end
    end
  end
end
