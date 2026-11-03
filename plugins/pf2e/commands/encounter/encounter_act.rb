module AresMUSH
  module Pf2e

    # What the `+e/act`, `+e/strike` and `+e/cast` commands share: who is acting and at whom, and telling
    # the room, the encounter's log and the scene what happened.
    #
    # Each takes the same shape of arguments - the thing done, `=` who it is done to, then `/` and the
    # circumstances - so a player learns one grammar:
    #
    #   +e/act trip=#3/flanking
    #   +e/strike #3=longsword/range 2
    #   +e/cast fear=#3,#4
    #
    # and a GM acting for a creature puts the creature first, the way `roll/for` does: `+e/as #3=strike
    # aria`.
    module ActsInEncounter

      # `trip=#3/flanking/range 2` as `[ 'trip', '#3', [ 'flanking', 'range 2' ] ]`.
      def self.split(args)
        parts = args.to_s.split('/').map(&:strip)
        head, _, tail = parts.shift.to_s.partition('=')

        [ head.strip, tail.strip, parts.reject(&:empty?) ]
      end

      # The one acting: the combatant the enactor plays, as they stand in the encounter. Nothing is done
      # outside one.
      def acting_as(encounter, actor = nil, doing = nil)
        return able(actor, doing) if actor
        return Err.new(:no_encounter, 'pf2e.no_encounter_here') unless encounter

        found = Combatants.find(encounter, enactor.name)

        return Err.new(:not_in_encounter, 'pf2e.act_join_first', 'id' => encounter.id) unless found.ok?

        able(found.state, doing)
      end

      # What leaves someone unable to act at all.
      HELPLESS = %w{Unconscious Paralyzed Petrified}.freeze

      # What someone paralyzed can still do: it takes only the mind.
      MIND_ONLY = [ 'Recall Knowledge' ].freeze

      # A creature with no hit points left, or anyone knocked out, paralyzed or turned to stone, does
      # nothing - but for answering the hit that knocked them out, which the rules have happen before it
      # lands, and for what a creature's stat block gives it to do as it drops.
      def able(combatant, doing = nil)
        holder = combatant.holder
        helpless = Pf2e.held_conditions(holder).keys & HELPLESS
        down = (Actors.of(holder).creature? && holder.hp_left.to_i <= 0) || helpless.any?

        return Ok.new(:state => combatant) unless down && !Acting.answering?(holder, doing)
        return Ok.new(:state => combatant) if helpless == [ 'Paralyzed' ] && mind_only?(doing)

        Err.new(:cannot_act, 'pf2e.act_cannot_act', 'actor' => combatant.label)
      end

      def mind_only?(doing)
        found = doing.to_s.strip.empty? ? nil : Actions.find(doing)

        !found.nil? && found.ok? && MIND_ONLY.include?(found.state)
      end

      def scene_for(encounter, actor, target)
        Acting::Scene.new(encounter, actor, target, enactor, Combatants.trusted?(enactor, encounter))
      end

      # Tells the room, and records it in the encounter and as a line of the scene's story. What only the
      # GM sees goes to them. `actor` is who did it, where it was something done in their turn.
      def tell(encounter, out, actor = nil)
        over_turn(encounter, actor, out) if actor
        message = Telling.lines(out['lines']).join('%r')

        if encounter
          Pf2e::Encounters::Announce.tell(encounter, message, :room => enactor_room, :story => true)
        else
          SystemPrefix.emit(enactor_room, message, 'action')
        end

        tell_gm(encounter, out['gm'])

        enactor.update(:pf2_last_roll => out['detail'])
      end

      # Said, and not refused, when what was just done takes someone past the actions their turn holds:
      # the game does not know everything a turn may be owed.
      def over_turn(encounter, actor, out)
        return unless encounter && ActiveEffects.current_turn(encounter) == actor.label

        used = TurnState.turn(actor.holder)['actions'].to_i
        total = TurnState.actions(actor.holder)

        out['lines'] << Telling.event('pf2e.act_over_turn', :actor => actor.label, :used => used, :total => total) if used > total
      end

      def tell_gm(encounter, lines)
        return if lines.empty?

        message = Telling.lines(lines).join('%r')
        gm = encounter && PF2Encounter.gm_of(encounter)

        if gm && gm != enactor
          Login.emit_ooc_if_logged_in(gm, message)
        elsif gm == enactor || !encounter
          client.emit_ooc message
        end
      end
    end

    # `+e/act <action>[=<target>,<target>...][/<circumstance>...]`
    class PF2EncounterActCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :action, :target, :words, :actor

      def parse_args
        self.action, self.target, self.words = ActsInEncounter.split(cmd.args)
      end

      def required_args
        [ self.action ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor, self.action)

        return if CharState.emit_error!(client, actor)

        named = self.target.to_s.split(',').map(&:strip).reject(&:empty?)
        targets, missing = Combatants.resolve_all(enactor, named, encounter)

        unless missing.empty?
          found = Combatants.resolve(enactor, missing.first, encounter)
          return if CharState.emit_error!(client, found)
        end

        done = Acting.act(scene_for(encounter, actor.state, targets.first), self.action, self.words,
                          :targets => targets)

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state, actor.state)
      end
    end

    # `+e/strike <target>[=<weapon>][/<circumstance>...]`
    class PF2EncounterStrikeCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :target, :weapon, :words, :actor

      def parse_args
        self.target, self.weapon, self.words = ActsInEncounter.split(cmd.args)
      end

      def required_args
        [ self.target ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor)

        return if CharState.emit_error!(client, actor)

        found = Combatants.resolve(enactor, self.target, encounter)

        return if CharState.emit_error!(client, found)

        done = Acting.strike(scene_for(encounter, actor.state, found.state), self.weapon, self.words)

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state, actor.state)
      end
    end

    # `+e/reload [<weapon>]` - load again a weapon that has been shot: as many actions as it takes.
    class PF2EncounterReloadCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :weapon, :actor

      def parse_args
        self.weapon = trim_arg(cmd.args)
      end

      def required_args
        []
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor)

        return if CharState.emit_error!(client, actor)

        done = Acting.reload(scene_for(encounter, actor.state, nil), self.weapon)

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state, actor.state)
      end
    end

    # `+e/cast <spell>[=<target>,<target>...][/rank <n>][/class <class>][/<circumstance>...]`
    #
    # A character's spell is cast through their magic first, which spends the slot, the focus point or the
    # use - and refuses where they have none - exactly as `cast` does. A creature's is cast from its stat
    # block's spellcasting.
    class PF2EncounterCastCmd
      include CommandHandler
      include ActsInEncounter

      attr_accessor :spell, :targets, :words, :actor

      # A switch `cast` takes that says which kind of casting spends the spell.
      KINDS = %w{focus focusc innate signature}.freeze

      def parse_args
        self.spell, targets, self.words = ActsInEncounter.split(cmd.args)
        self.targets = targets.split(',').map(&:strip).reject(&:empty?)
      end

      def required_args
        [ self.spell ]
      end

      def handle
        encounter = Combatants.encounter_here(enactor)
        actor = acting_as(encounter, self.actor)

        return if CharState.emit_error!(client, actor)

        found, missing = Combatants.resolve_all(enactor, self.targets, encounter)

        unless missing.empty?
          client.emit_failure t('pf2e.no_combatant', :target => missing.join(', '))
          return
        end

        # Asked before the spell is spent, so a caster who has to choose loses nothing by not having.
        return if CharState.emit_error!(client, Acting.way_needed(self.spell, self.words))

        # A caster who cannot cast it at all is refused before the spell is spent.
        scene = scene_for(encounter, actor.state, nil)
        return if CharState.emit_error!(client, Acting.unlisted_spell(scene, self.spell, self.words) || Ok.new(:state => nil))
        return if CharState.emit_error!(client, Acting.casting_refused(scene, self.spell, self.words) || Ok.new(:state => nil))
        return if CharState.emit_error!(client, UntamedForm.refusal(scene, self.spell, self.words, found) || Ok.new(:state => nil))

        cast = Actors.of(actor.state.holder).spends_spells? ? spend_the_spell(actor.state.holder) : nil

        if cast.is_a?(String)
          client.emit_failure cast
          return
        end

        spell = cast.is_a?(Hash) ? cast['spell name'] : self.spell

        # One who may not get it off rolls for it with the spell spent, and loses it with its actions.
        risked = Acting.casting_risked(scene, spell)
        return tell(encounter, Acting.casting_lost(scene, spell, risked, cast).state, actor.state) if risked && !risked['kept']

        done = Acting.cast(scene, spell, found, self.words, :cast => cast, :noted => risked ? risked['lines'] : [])

        return if CharState.emit_error!(client, done)

        tell(encounter, done.state, actor.state)
      end

      # The caster's magic spends the spell and answers with what it was cast at, or says why it could not.
      def spend_the_spell(char)
        said = Acting.said(self.words, false)
        kind = self.words.map(&:downcase).find { |word| KINDS.include?(word) }

        # A spell a feat grants innately - Storm's Lash's Electric Arc - is cast as one without the
        # player having to say so, where no class they cast from knows it. A Fighter has no class to
        # cast from at all, and was told they had no magical ability.
        kind ||= 'innate' if !said['class'] && innate_by_default?(char)

        charclass = if said['class']
          said['class'].split.map(&:capitalize).join(' ')
        elsif kind != 'innate'
          casting_class(char)
        end

        level = said['rank'] ? said['rank'].to_s : nil

        return t('pf2emagic.not_caster') unless charclass || kind == 'innate'

        Pf2emagic.cast_spell(char, charclass || 'Innate', self.spell, [], level, kind)
      end

      # Which of their casting classes casts it, where they did not say: the one that knows the spell, and
      # otherwise the only one they have. A spellcasting entry is named by `name`.
      def casting_class(char)
        return nil unless char.magic

        entries = Pf2emagic::Entries.casting(char.magic)
        knows = entries.find { |entry| knows_spell?(char.magic, entry['name']) }

        (knows || entries.first)&.dig('name')
      end

      # Known innately, by the name the cast itself would resolve, and known to none of their classes.
      def innate_by_default?(char)
        magic = char.magic
        return false unless magic

        found = Pf2emagic.get_spell_details(self.spell)
        name = found.is_a?(Array) ? found[0] : self.spell

        return false unless Pf2emagic::Entries.knows_innate?(magic, name)

        Pf2emagic::Entries.casting(magic).none? { |entry| knows_spell?(magic, entry['name']) }
      end

      def knows_spell?(magic, source)
        Pf2emagic::Entries.known(magic, source).values.flatten.any? { |spell| spell.to_s.casecmp?(self.spell.to_s) }
      end
    end

    # `+e/as <combatant>=<act|strike|cast> <what>` - a GM acting for a creature, or for anyone in the
    # encounter.
    class PF2EncounterAsCmd
      include CommandHandler

      attr_accessor :who, :verb, :rest

      # Asked for rather than held in a constant, because the aura command is defined in a file loaded
      # after this one.
      def self.verbs
        { 'act' => PF2EncounterActCmd, 'strike' => PF2EncounterStrikeCmd, 'cast' => PF2EncounterCastCmd,
          'reload' => PF2EncounterReloadCmd, 'enter' => PF2EncounterAuraCmd, 'leave' => PF2EncounterAuraCmd }
      end

      def parse_args
        self.who, _, command = cmd.args.to_s.partition('=')
        self.verb, _, self.rest = command.strip.partition(' ')
        self.who = self.who.strip
        self.verb = self.verb.downcase
      end

      def required_args
        [ self.who, self.verb ]
      end

      def check_verb
        return nil if self.class.verbs.key?(self.verb)

        t('pf2e.bad_option', :element => 'command', :options => self.class.verbs.keys.join(', '))
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter
        return client.emit_failure(t('pf2e.not_organizer')) unless Combatants.gm?(enactor, encounter)

        actor = Combatants.find(encounter, self.who)

        return if CharState.emit_error!(client, actor)

        handler = self.class.verbs[self.verb].new(client, Command.new("e/#{self.verb} #{self.rest}"), enactor)
        handler.parse_args
        handler.actor = actor.state

        missing = handler.required_args.any? { |one| one.to_s.empty? }

        return client.emit_failure(t('dispatcher.invalid_syntax', :cmd => "e/#{self.verb}")) if missing

        handler.handle
      end
    end

    # `+e/why` - every modifier of the last roll you made or made for someone.
    class PF2EncounterWhyCmd
      include CommandHandler

      def handle
        events = Array(enactor.pf2_last_roll)

        return client.emit_ooc(t('pf2e.why_nothing')) if events.empty?

        client.emit Telling.lines(events).join('%r')
      end
    end

    # `+e/turn [<combatant>]` - what you, or a combatant, have done this turn.
    class PF2EncounterTurnCmd
      include CommandHandler

      attr_accessor :who

      def parse_args
        self.who = trim_arg(cmd.args)
      end

      def handle
        encounter = Combatants.encounter_here(enactor)

        return client.emit_failure(t('pf2e.not_in_active_encounter')) unless encounter

        found = Combatants.find(encounter, self.who || whose_turn(encounter))

        return if CharState.emit_error!(client, found)

        return client.emit_ooc(t('pf2e.turn_dead', :name => found.state.label)) if Pf2e.dead?(found.state.holder)

        client.emit_ooc t('pf2e.turn_of', :name => found.state.label, :summary => TurnState.summary(found.state.holder))
      end

      # Their own turn, for someone in the fight; for anyone else - its GM - that of whoever is acting.
      def whose_turn(encounter)
        Combatants.find(encounter, enactor.name).ok? ? enactor.name : ActiveEffects.current_turn(encounter)
      end
    end
  end
end
