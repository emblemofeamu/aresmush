module AresMUSH
  module Pf2egear

    # The gear commands in an encounter, on what a character carries there: the encounter's copy of their
    # gear, taken as they entered it (`Pf2e::Equipment`). Outside, the same commands work on their own.
    # Held here rather than in commands/ because each extends a command defined there, which loads first.
    module EncounterGear
      def holder
        return @holder if defined?(@holder)

        encounter = Pf2e::Combatants.encounter_here(enactor)
        @holder = encounter ? Pf2e::CombatantStates.of(encounter, enactor) : nil
      end

      def check_in_encounter
        holder ? nil : t('pf2e.encounter_gear_not_in')
      end

      # A battle form absorbs what they carry. Named to follow the check above.
      def check_in_form
        holder && Pf2e::BattleForms.active?(holder) ? t('pf2e.form_gear_absorbed', :actor => enactor.name) : nil
      end
    end

    # `+e/use <category>=<number>[/<use>]`, and for a consumable `+e/use consumables=<number>[/<who>]`:
    # drunk, or given to someone else in the fight, it does what the catalogue says (`Pf2e::Consumables`).
    class PF2EncounterUseCmd < PF2UseItemCmd
      include EncounterGear
      include Pf2e::ActsInEncounter

      def consumable?
        self.category.to_s.match?('consumable')
      end

      # Named for where it falls among the checks, which run in the order of their names: after the one
      # that finds them in the encounter, and before anything is used.
      def check_what_it_does
        return nil unless holder && consumable?

        found = Pf2egear::Inventory.item(holder, self.category, self.item_num)

        return nil if found.err? || !found.state
        return t('pf2e.consumable_throw_it', :item => found.state.name) if Pf2e::Consumables.bomb?(found.state.name)

        material = Pf2e::Ammunition.material(found.state.name)
        return t('pf2e.ammunition_shoot_it', :item => found.state.name, :material => material.tr('-', ' ')) if material

        encounter = Pf2e::Combatants.encounter_here(enactor)
        whom = self.use_option ? Pf2e::Combatants.resolve(enactor, self.use_option, encounter)
                               : Pf2e::Combatants.find(encounter, enactor.name)

        return t(whom.key, **Pf2e::CharState.symbolize(whom.args)) if whom.err?

        @taker = whom.state
        # Whoever drinks their own is one and the same: what the potion does and the action it takes are
        # written to the one copy of them.
        own = Pf2e::Combatants.find(encounter, enactor.name)
        @user = own.ok? && own.state.label == whom.state.label ? whom : own
        able = @user.ok? ? able(@user.state) : @user

        return t(able.key, **Pf2e::CharState.symbolize(able.args)) if able.err?

        cannot_take(found.state.name)
      end

      # Someone sickened cannot willingly swallow anything.
      def cannot_take(name)
        swallowed = (Array(Pf2e::Consumables.info(name)['traits']) & %w{potion elixir}).any?

        return nil unless swallowed && Pf2e.held_conditions(@taker.holder).key?('Sickened')

        t('pf2e.sickened_cannot_ingest', :target => @taker.label, :item => name)
      end

      # It takes an action to use.
      def consumed(item)
        encounter = Pf2e::Combatants.encounter_here(enactor)
        out = Pf2e::Consumables.take(encounter, enactor.name, @taker, item.name)

        Pf2e::TurnState.spend(@user.state.holder, 'Interact', :cost => 1, :type => 'action')
        tell(encounter, out, @user.state)
      end
    end

    # `+e/equip <category>=<number>` - draw a weapon, put on armour, strap on a shield.
    class PF2EncounterEquipCmd < PF2GearEquipCmd
      include EncounterGear
    end

    # `+e/unequip <category>=<number>` - stow it again.
    class PF2EncounterUnequipCmd < PF2GearUnequipCmd
      include EncounterGear
    end

    # `+e/gear [<combatant>]` - what a character carries in the encounter here.
    class PF2EncounterGearCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        encounter = Pf2e::Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter

        found = Pf2e::Combatants.find(encounter, self.who || enactor.name)

        return if Pf2e::CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        char = Pf2e::Actors.of(found.state.holder).person
        allowed = Pf2e::Sheet.viewable?(enactor, char, 'combat')

        return if Pf2e::CharState.emit_error!(client, allowed)

        client.emit Pf2eDisplayGearTemplate.new(found.state.holder, client).render
      end
    end

    # `+e/loot <combatant>=<consumable>[/<quantity>]` - gives someone a consumable in the encounter here,
    # from the catalogue, at no cost. Staff, and the trusted GMs an admin gives `trusted_gm` to; an
    # encounter's own GM does not give things out. What it gives is the encounter's: it is theirs to use
    # there, and goes no further when the encounter ends.
    class PF2EncounterLootCmd
      include CommandHandler

      attr_accessor :who, :category, :item_name, :quantity

      def parse_args
        who, _, what = cmd.args.to_s.partition('=')
        named, _, quantity = what.strip.rpartition('/')
        named = what.strip if named.empty?

        self.who = who.strip
        self.category = 'consumables'
        self.item_name = named.strip.downcase
        self.quantity = quantity.to_i.positive? ? quantity.to_i : 1
      end

      def required_args
        [ self.who, self.item_name ]
      end

      def check_may_give
        return nil if enactor.is_admin?
        return t('pf2e.loot_not_trusted') unless enactor.has_permission?('trusted_gm')

        nil
      end

      def handle
        encounter = Pf2e::Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.no_encounter_here')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless enactor.is_admin? || Pf2e::Combatants.gm?(enactor, encounter)

        found = Pf2e::Combatants.find(encounter, self.who)

        return if Pf2e::CharState.emit_error!(client, found)
        return client.emit_failure(t('pf2e.encounter_sheet_creature', :ref => found.state.ref)) if found.state.creature?

        name, info = catalogue_entry

        return client.emit_failure(t('pf2egear.not_found')) unless name

        Pf2e::Equipment.grant!(found.state.holder, self.category, name, self.quantity, info,
                               :granted_by => 'loot', :expires => 'encounter')

        message = t('pf2e.loot_given', :name => enactor.name, :item => name, :many => self.quantity, :who => found.state.label)

        client.emit_success message
        Pf2e::SystemPrefix.emit(enactor_room, message, 'system', :ooc => true)
      end

      # The item by name, exactly or as the only one holding the words typed.
      def catalogue_entry
        list = Global.read_config(Pf2egear::Inventory.config(self.category)) || {}
        exact = list.find { |named, _info| named.downcase == self.item_name }

        return exact if exact

        found = list.select { |named, _info| named.downcase.include?(self.item_name) }

        found.size == 1 ? found.first : nil
      end
    end

    [ PF2EncounterUseCmd, PF2EncounterEquipCmd, PF2EncounterUnequipCmd,
      PF2EncounterLootCmd ].each { |command| command.prepend(Pf2e::Recorded) }
  end
end
