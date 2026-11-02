module AresMUSH
  module Pf2e

    # Plays an encounter the way a GM and a party of players would: every step is a command one of them
    # types, read back through what the game told them. It records each thing a player tried - a Strike
    # with each weapon they carry, each action their feats and features give them, each spell they can
    # cast, each item they can use - and what came of it, so a scenario's report says what a character
    # of that class and level could and could not do.
    #
    # The room's and the GM's messages are written to the transcript by whoever drives the runner, which
    # stubs the emitters (`#heard`).
    class ScenarioRunner
      include InteractionProbes
      include ExplorationPlay
      include GmProbes
      include CreaturePlay

      # One player's seat: the character's class and origin, and what they carry.
      #
      #   kit: { 'weapons' => [ 'Longsword' ], 'armor' => 'Full Plate', 'shields' => 'Steel Shield',
      #          'consumables' => [ [ 'Healing Potion (Minor)', 2 ] ],
      #          'runes' => { 'potency' => 1, 'striking' => 1, 'resilient' => 0, 'armor_potency' => 1,
      #                       'property' => [ 'Flaming' ] },
      #          'alchemy' => [ 'Alchemist's Fire (Lesser)' ] }
      Seat = Struct.new(:charclass, :ancestry, :heritage, :background, :kit, keyword_init: true)

      # What one command did: who typed it, what they typed, what they and the room were told, and anything
      # it raised.
      Outcome = Struct.new(:who, :text, :said, :room, :failures, :error, keyword_init: true) do
        def ok?
          failures.empty? && error.nil?
        end

        def status
          return "ERROR #{error.class}: #{error.message}" if error
          return "refused: #{failures.join(' / ')}" unless failures.empty?

          'ok'
        end
      end

      # A thing a player tried, by kind, and how it went.
      Try = Struct.new(:who, :kind, :what, :text, :outcome, keyword_init: true)

      MUSH_CODES = /%[xX][a-zA-Z]|%[xX]\d{1,3}|%[cC][a-zA-Z]|%[cC]\d{1,3}|%l[a-z]|%n|%t|%b/

      # The plugins a typed command can reach: the game's own and the scenes it is played in.
      PLAYED = AutoBuilder::PLUGINS + [ 'Scenes' ]

      attr_reader :name, :level, :seats, :waves, :lines, :tries, :outcomes, :party, :gm, :staff, :encounters,
                  :build_notes, :audit, :probes, :explorations, :scene, :gm_kind

      # The role a Plotmaster holds, which carries the one permission that makes them one.
      PLOTMASTER = 'plotmaster'.freeze

      # `gm_kind` is who runs the fights: `:staff`, a `:plotmaster`, or a `:runner` - any approved
      # character. Whoever it is, the party's runes are etched by staff.
      def initialize(name, level:, seats:, waves:, rounds: 6, gm_kind: :staff)
        @name = name
        @level = level
        @seats = seats
        @waves = waves
        @rounds = rounds
        @gm_kind = gm_kind
        @lines = []
        @tries = []
        @outcomes = []
        @party = []
        @encounters = []
        @build_notes = {}
        @tried = Hash.new { |h, k| h[k] = {} }
        @audit = RollAudit.new
        @probes = []
        @told_gm = []
        @told_room = []
        @explorations = []
      end

      # ------------------------------------------------------------------------------
      # The transcript

      # What leaks the engine's insides into what a player reads.
      LEAKS = /Translation missing|=>|%\{|#<[A-Z]|undefined method|\bnil\b/

      def heard(message, to = nil)
        text = clean(message)

        return if text.empty?

        @audit.find('wording', to ? "told #{to}" : 'told the room', text[0, 200]) if text.match?(LEAKS)
        @told_gm << text if @gm && to == @gm.name
        @told_room << text unless to

        @lines << (to ? "    [to #{to}] #{text}" : "    #{text}")
      end

      def clean(message)
        message.to_s.gsub(MUSH_CODES, '').gsub('%r', "\n      ").gsub(/%R/, "\n      ").strip
      end

      def say(text)
        @lines << text
      end

      # ------------------------------------------------------------------------------
      # Typing a command

      def type(char, text)
        client = AutoBuilder::CaptureClient.new
        cmd = Command.new(text)
        enactor = Character[char.id]
        handler = PLAYED.lazy.map { |plugin|
          (AresMUSH.const_get(plugin).get_cmd_handler(client, cmd, enactor) rescue nil)
        }.find { |found| found }
        error = nil
        told = @told_room.size

        say "  > #{enactor.name}: #{text}"

        begin
          raise "no command answers #{text}" unless handler

          handler.new(client, cmd, enactor).on_command
        rescue StandardError => e
          error = e
        end

        (client.successes + client.oocs).each { |line| heard(line, enactor.name) }
        client.failures.each do |line|
          @lines << "    !! #{clean(line)}"
          @audit.find('wording', "#{enactor.name}: #{text}", clean(line)[0, 200]) if clean(line).match?(LEAKS)
        end
        @lines << "    ** #{error.class}: #{error.message} (#{error.backtrace&.first})" if error

        outcome = Outcome.new(:who => enactor.name, :text => text, :said => client.successes + client.oocs,
                              :room => @told_room[told..],
                              :failures => client.failures.map { |line| clean(line) }, :error => error)
        @outcomes << outcome
        outcome
      end

      def attempt(char, kind, what, text)
        outcome = type(char, text)

        @tries << Try.new(:who => char.name, :kind => kind, :what => what, :text => text, :outcome => outcome)
        @tried[char.id][[ kind, what ]] = outcome
        @audit.safely("#{char.name}: #{text}") { spell_outcome!(char, text) } if outcome.ok? && text.start_with?('e/cast') && !lost?(outcome)
        outcome
      end

      # A spell lost to a flat check - its caster grabbed, deafened or stupefied - does nothing to read.
      def lost?(outcome)
        (outcome.said + outcome.room).any? { |line| line.to_s.include?('The action is lost') }
      end

      # ------------------------------------------------------------------------------
      # Before the fight

      def stage!
        @room = Room.create(:name => "#{@name} Hall #{rand(1000000)}")
        # A temporary room's, so the running game's empty-scene cleanup does not stop it mid-play
        # (see ExplorationPlay#stage_scene!).
        @scene = Scene.create(:room => @room, :title => @name, :temp_room => true)
        @room.update(:scene => @scene)
        seat_gm!

        say "# #{@name}: a party of #{@seats.size} at level #{@level}, run by #{Gm.kind(@gm)}"
        say ''
      end

      # The GM, and the staff member who outfits the party - the same character where the GM is staff.
      def seat_gm!
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        Roles.add_role(@gm, 'approved')

        if @gm_kind == :plotmaster
          Role.create(:name => PLOTMASTER, :permissions => [ 'kill_pc' ]) unless Role.find_one_by_name(PLOTMASTER)
          Roles.add_role(@gm, PLOTMASTER)
        end

        @gm = Character[@gm.id]
        @staff = @gm_kind == :staff ? @gm : Character.create(:name => "Staff#{rand(1000000)}", :room => @room)
      end

      def gm_name
        @gm.name
      end

      def build_party!
        @seats.each_with_index do |seat, i|
          char = Character.create(:name => "#{seat.charclass}#{@level}x#{rand(100000)}", :room => @room)
          builder = AutoBuilder.new(char)

          builder.build_level_one(seat.charclass, ancestry: seat.ancestry, heritage: seat.heritage,
                                                  background: seat.background)
          builder.advance_to(@level)

          char = Character[char.id]
          @build_notes[char.name] = builder.notes.select { |note| note.start_with?('!!', '??', 'level') }
          @party << char
          Scene[@scene.id].participants.add(char)

          say "## #{char.name}: level #{char.pf2_level} #{char.pf2_base_info['ancestry']} " \
              "(#{char.pf2_base_info['heritage']}) #{seat.charclass}, #{char.pf2_base_info['background']}"
          say "  feats: #{(char.pf2_feats || {}).values.flatten.join(', ')}"
          choices = (char.pf2_level_tracker || {}).values.map { |entry| entry['feat_choices'] }.compact.reduce({}, :merge)
          say "  feat choices: #{choices.map { |feat, choice| "#{feat}: #{Array(choice).join('/')}" }.join(', ')}" unless choices.empty?
          say "  build notes: #{@build_notes[char.name].join(' | ')}" unless @build_notes[char.name].empty?
        end

        say ''
      end

      # A kit is what the character would choose, so one they are untrained in is the scenario's mistake.
      def wear!(char, text)
        untrained = type(char, text).said.map { |line| clean(line) }.find { |line| line.start_with?('You are untrained') }

        @audit.find('kit', "#{char.name}: #{text}", untrained) if untrained
      end

      # Money to spend, then the kit: bought, worn and wielded by the player, its runes etched by staff.
      def outfit!
        say '## Outfitting'

        @party.each_with_index do |char, i|
          kit = @seats[i].kit || {}

          Pf2egear.pay_player(char, 50_000_000, 'Scenario', 'Starting wealth')

          Array(kit['weapons']).each { |weapon| type(char, "buy weapons=#{weapon}") }
          type(char, "buy armor=#{kit['armor']}") if kit['armor']
          type(char, "buy shields=#{kit['shields']}") if kit['shields']
          Array(kit['consumables']).each { |item, count| type(char, "buy consumables=#{item}/#{count || 1}") }

          Array(kit['weapons']).each_index { |n| wear!(char, "equip weapons=#{n}") }
          wear!(char, 'equip armor=0') if kit['armor']
          type(char, 'equip shields=0') if kit['shields']

          etch!(char, kit['runes'] || {}, Array(kit['weapons']).size, kit['armor'])
          prepare_spells!(char)
          prepare_alchemy!(char, Array(kit['alchemy']))
          type(char, 'gear')
        end

        say ''
      end

      def etch!(char, runes, weapons, armor)
        weapons.times do |n|
          type(@staff, "etch/potency #{char.name}=weapons/#{n}/#{runes['potency']}") if runes['potency'].to_i > 0
          type(@staff, "etch/striking #{char.name}=weapons/#{n}/#{runes['striking']}") if runes['striking'].to_i > 0
          Array(runes['property']).each { |rune| type(@staff, "etch/property #{char.name}=weapons/#{n}/#{rune}") }
        end

        return unless armor

        type(@staff, "etch/potency #{char.name}=armor/0/#{runes['armor_potency']}") if runes['armor_potency'].to_i > 0
        type(@staff, "etch/resilient #{char.name}=armor/0/#{runes['resilient']}") if runes['resilient'].to_i > 0
      end

      # A prepared caster fills every slot they have, with spells that do something in a fight first.
      def prepare_spells!(char)
        magic = Character[char.id].magic

        return unless magic

        (magic.tradition || {}).keys.reject { |key| key == 'innate' }.each do |charclass|
          next unless Pf2emagic.get_caster_type(charclass) == 'prepared'

          (magic.spells_per_day[charclass] || {}).each_pair do |rank, count|
            candidates = preparable(char, charclass, rank)
            filled = 0

            candidates.each do |spell|
              break if filled >= count.to_i

              filled += 1 if type(char, "prepare #{charclass}/#{rank.to_s == 'cantrip' ? 0 : rank}=#{spell}").ok?
            end
          end
        end

        type(char, 'prepared')
      end

      def preparable(char, charclass, rank)
        char = Character[char.id]
        known = Pf2emagic::Entries.known_lists(char)[charclass]
        pool = if known && !known.empty?
                 Array(known[rank.to_s])
               else
                 AutoBuilder.new(char).spell_pool(rank.to_s == 'cantrip' ? 'cantrip' : rank.to_i, charclass)
               end

        # Two of each where a list is short, so a rank's every slot is filled.
        ordered = pool.sort_by { |spell| fighting?(spell) ? 0 : 1 }
        ordered + ordered
      end

      def fighting?(spell)
        mechanics = Global.read_config('pf2e_spell_mechanics', spell) || {}

        %w{save attack damage outcomes}.any? { |key| mechanics.key?(key) } || healing?(spell)
      end

      def healing?(spell)
        traits = Array((Global.read_config('pf2e_spells', spell) || {})['traits'])

        traits.include?('healing')
      end

      def prepare_alchemy!(char, items)
        return if items.empty?

        items.each do |item|
          type(@staff, "formulas/add #{char.name}=consumables/#{item}")
          type(char, "alchemy/prepare #{item}/2")
        end

        type(char, 'alchemy')
      end

      # ------------------------------------------------------------------------------
      # The fight

      def encounter
        @encounter && PF2Encounter[@encounter.id]
      end

      # Why a start left no encounter running in the scene: what the game said to the command, how the
      # scene stands, and every encounter its GM still runs, wherever it is - the likeliest thing in the way.
      def unstarted(what, outcome)
        scene = Scene[@scene.id]
        held = scene.encounters.to_a.map { |one| "##{one.id} #{one.is_active ? 'active' : 'ended'}" }
        running = PF2Encounter.find(:owner_id => @gm.id).to_a.select(&:is_active)
                              .map { |one| "##{one.id} (#{one.mode || 'fight'}) in scene #{one.scene&.id || 'none'}" }

        [ "#{@name}: the GM could not start #{what}",
          "the game said: #{outcome.status}#{outcome.said.empty? ? '' : " - #{outcome.said.map { |line| clean(line) }.join(' / ')[0, 300]}"}",
          "scene #{scene.id} #{scene.completed ? 'stopped' : 'running'}, holding #{held.empty? ? 'no encounter' : held.join(', ')}",
          "the GM still runs #{running.empty? ? 'no encounter' : running.join(', ')}" ].join('; ')
      end

      # A fight: carrying on from the one before, or - started while the party explores - taking over
      # from the exploration, which brings everyone into it with initiative rolled.
      def fight!(wave, carries_on: nil, from_exploration: false)
        @wave = wave
        say "## Encounter: #{wave.map { |entry| adding(entry) }.join(', ')}"

        started = type(@gm, carries_on ? "encounter =#{carries_on.id}" : 'encounter')
        @encounter = PF2Encounter.scene_active_encounter(Scene[@scene.id])

        raise unstarted('an encounter', started) unless @encounter

        @encounters << @encounter

        unless from_exploration
          @party.each { |char| type(char, 'e/join') }
          type(@gm, 'e/rest') unless carries_on
        end
        wave.each { |entry| type(@gm, "e/add #{adding(entry)}") }
        type(@gm, 'e/view')
        type(@gm, 'e/scan')
        type(@gm, 'e/next')
        interactions!
        gm_probes!

        @rounds.times do |round|
          break if foes.empty?

          say "### Round #{round + 1}"
          order_size = Combatants.rows(encounter).size

          order_size.times do
            ending = frightened_before_turn_ends
            heard_before = @lines.size
            type(@gm, 'e/next')
            @audit.safely('frightened easing') { frightened_eased!(ending) }
            @audit.safely('recovery check') { recovery_rolled!(@lines[heard_before..]) }
            break if foes.empty?

            act_on_turn
          end

          rescue_the_fallen
        end

        type(@gm, 'e/history')
        type(@gm, 'e/undo')
        type(@gm, 'e/redo')
        # Rewards are staff's to pay, whoever ran the fight.
        type(@staff, "e/award #{encounter.id}")
        @party.each { |char| type(@staff, "e/award #{encounter.id}=#{char.name}=80/10 gp") }
        type(@gm, "encounter/end #{encounter.id}")

        say ''
        @encounter
      end

      # What the GM types after `e/add` for one entry of a wave: a count and a creature, or - for a
      # creature of the GM's own making - the whole of it.
      def adding(entry)
        entry.is_a?(String) ? entry : entry.join(' ')
      end

      def act_on_turn
        name = ActiveEffects.current_turn(encounter)
        row = Combatants.rows(encounter).find { |one| one['name'] == name }

        return unless row

        if row['npc']
          creature_turn(row) if Pf2eNpc[row['npc']]&.hp_left.to_i.positive?
        elsif row['char']
          player_turn(Character[row['char']])
        end
      end

      def foes
        Combatants.rows(encounter).select { |row| row['npc'] && Pf2eNpc[row['npc']] && Pf2eNpc[row['npc']].hp_left > 0 }
      end

      def foe
        foes.min_by { |row| Pf2eNpc[row['npc']].hp_left }
      end

      def state_of(char)
        CombatantStates.of(encounter, Character[char.id])
      end

      def hp_of(char)
        state = state_of(char)

        state ? Pf2eHP.get_current_hp(state) : 0
      end

      def max_hp_of(char)
        state = state_of(char)

        state ? Pf2eHP.get_max_hp(state) : 0
      end

      def down?(char)
        hp_of(char) <= 0 || Pf2e.dead?(state_of(char))
      end

      def standing
        @party.reject { |char| down?(char) }
      end

      # Those of the party who can act: standing, and neither unconscious, paralyzed nor petrified.
      def able
        standing.reject do |char|
          state = state_of(char)

          state && (Pf2e.held_conditions(state).keys & ActsInEncounter::HELPLESS).any?
        end
      end

      # The GM's correction for a player knocked out: what play at a table would be the cleric's next
      # action, here so that everyone plays every round. The GM is staff, whose fight kills, so the dead
      # are brought back first.
      def rescue_the_fallen
        @party.select { |char| down?(char) }.each do |char|
          raise_if_dead(char)
          type(@gm, "condition/set #{char.name}=dying/0")
          type(@gm, "heal #{char.name}=#{max_hp_of(char)}")
        end
      end

      def raise_if_dead(char)
        return unless Pf2e.dead?(state_of(char))

        @audit.counts['characters killed'] += 1
        type(@gm, "condition/set #{char.name}=dead/0")
      end

      # ------------------------------------------------------------------------------
      # A creature's turn: its GM strikes the player with the most hit points left and, the first time,
      # uses one of its own abilities or spells. The probes knock a character out on purpose; spreading
      # the blows lets everyone play the fight through.

      # ------------------------------------------------------------------------------
      # A player's turn: up to three things they have not yet tried, else a Strike.

      def player_turn(char)
        return if down?(char)

        # Someone who starts their turn on the ground gets up first, and someone held gets free.
        type(char, 'e/act stand') if (state_of(char).pf2_conditions || {}).key?('Prone')
        struggle(char)
        # A crossbow shot last turn is loaded before anything else is done with it.
        type(char, 'e/reload') if Loading.held(state_of(char)).any?

        agenda = (@agendas ||= {})[[ char.id, encounter.id ]] ||= agenda_for(char)
        undone = agenda.reject { |kind, what, _text| @tried[char.id].key?([ kind, what ]) }
        undone = undone.sort_by { |kind, _what, _text| kind == :heal ? 0 : 1 } if ally_hurt?

        # A command that cannot be typed yet - Drain Bonded Item before a spell is cast - waits.
        undone.lazy.map { |kind, what, text| [ kind, what, text.respond_to?(:call) ? text.call : text ] }
              .select { |_kind, _what, command| command }.first(3).each do |kind, what, command|
          break if foes.empty?

          attempt(char, kind, what, command)
          gm_reacts!(char, kind)
        end

        return unless undone.empty? && foe

        attempt(char, :strike, 'again', "e/strike ##{foe['id']}")
      end

      def ally_hurt?
        @party.any? { |char| hp_of(char) < max_hp_of(char) / 2 }
      end

      def hurt_ally
        @party.min_by { |char| hp_of(char).to_f / [ max_hp_of(char), 1 ].max }
      end

      def foe_ref
        -> { "##{(foe || {})['id']}" }
      end

      # Everything this character can try, as [ kind, what, command ]. A command is a lambda where its
      # target is chosen when it is typed.
      def agenda_for(char)
        state = state_of(char)
        out = []

        out << [ :look, 'sheet', 'e/sheet' ]
        out << [ :look, 'gear', 'e/gear' ]
        out << [ :look, 'turn', 'e/turn' ]

        Array(state.weapons.to_a).each_with_index do |weapon, n|
          name = weapon.name
          out << [ :strike, name, -> { "e/strike #{foe_ref.call}=#{name}" } ]
          out << [ :equipment, "unequip #{name}", "e/unequip weapons=#{n}" ] if n.zero?
          out << [ :equipment, "equip #{name}", "e/equip weapons=#{n}" ] if n.zero?
        end
        out << [ :strike, 'fist', -> { "e/strike #{foe_ref.call}=fist" } ]
        out << [ :look, 'why', 'e/why' ]

        out << [ :act, 'Raise a Shield', 'e/act raise a shield' ] unless state.shields.to_a.empty? || ShieldBlock.cannot_raise(state)
        out << [ :act, 'Demoralize', -> { "e/act demoralize=#{foe_ref.call}" } ]

        # A healing action is for whoever is worst hurt; anything else is aimed at a foe. Shield Block and
        # Nimble Dodge answer a hit, and are used when one offers them.
        answers = [ ShieldBlock::NAME ] + AttackAnswers.reactions(state)
        own_actions(char, state).each do |action|
          next if answers.include?(action) || Acting::COMMANDS.key?(Domains.slug(action))
          next if Exploration.only_exploring?(action, Actions.info(action))

          if action == BondedItem::NAME
            out << [ :ability, action, -> { (spell = cast_today(char)) && "e/act #{action.downcase}/#{spell}" } ]
          elsif Array(Actions.info(action)['traits']).include?('healing')
            out << [ :heal, action, -> { "e/act #{action}=#{hurt_ally.name}" } ]
          else
            out << [ :ability, action, -> { "e/act #{action}=#{foe_ref.call}" } ]
          end
        end

        spells_for(char, state).each { |entry| out << entry }

        # A bomb is thrown at a foe; anything else is drunk, or given to whoever is worst hurt.
        state.consumables.to_a.each_with_index do |item, n|
          name = item.name

          if Consumables.bomb?(name)
            out << [ :strike, name, -> { "e/strike #{foe_ref.call}=#{name}" } ]
          elsif Consumables.info(name)['heal']
            out << [ :heal, name, -> { "e/use consumables=#{n}/#{hurt_ally.name}" } ]
          else
            out << [ :item, name, "e/use consumables=#{n}" ]
          end
        end

        out << [ :refocus, 'refocus', 'e/refocus' ] if Pf2emagic.focus_pool_max(Character[char.id].magic).to_i > 0

        (Character[char.id].pf2_alchemy_plan || {}).each_key { |item| out << [ :alchemy, item, "e/alchemy #{item}" ] }

        out
      end

      # A spell they prepared today and have cast, which Drain Bonded Item gives back.
      def cast_today(char)
        magic = state_of(char).magic

        return nil unless magic

        (magic.spells_prepared || {}).each do |charclass, ranks|
          (ranks || {}).each do |rank, spells|
            next if rank.to_s == 'cantrip'

            left = Array(((magic.spells_today || {})[charclass] || {})[rank])
            Array(spells).uniq.each { |spell| return spell if Array(spells).count(spell) > left.count(spell) }
          end
        end

        nil
      end

      # What the game offers them, and what their class, heritage and background say they have, by the
      # names the catalogue holds.
      def own_actions(char, state)
        granted = Array((Character[char.id].pf2_actions || {})['actions'])
        named = granted.map { |action| (found = Actions.find(action)).ok? ? found.state : action }

        (class_actions(state) + named).uniq { |action| Domains.slug(action) }
      end

      # The actions a character's own feats and features give them, which no one else has.
      def class_actions(state)
        Actions.available(state, 'combat').reject { |name| Actions.info(name)['for'] == 'everyone' }
      end

      def spells_for(char, state)
        magic = state.magic

        return [] unless magic

        out = []
        today = magic.spells_today || {}

        (magic.tradition || {}).keys.reject { |key| key == 'innate' }.each do |charclass|
          casting = Pf2emagic.get_caster_type(charclass)
          slots = today[charclass] || {}

          if casting == 'prepared'
            slots.each_pair do |rank, spells|
              Array(spells).uniq.each { |spell| out << cast_entry(spell, rank, charclass) }
            end
          else
            known = Pf2emagic::Entries.known_lists(Character[char.id])[charclass] || {}

            known.each_pair do |rank, spells|
              next unless rank.to_s == 'cantrip' || slots[rank.to_s].to_i > 0

              Array(spells).first(rank.to_s == 'cantrip' ? 5 : 2).each { |spell| out << cast_entry(spell, rank, charclass) }
            end
          end
        end

        Pf2emagic::Entries.focus_types(magic).each do |focus_type|
          Pf2emagic::Entries.focus_spells(magic, focus_type).each { |spell| out << cast_entry(spell, nil, nil, 'focus') }
          Pf2emagic::Entries.focus_cantrips(magic, focus_type).each { |spell| out << cast_entry(spell, nil, nil, 'focusc') }
        end

        Array(today['innate']).each { |rank, spells| Array(spells).each { |spell| out << cast_entry(spell, rank, nil, 'innate') } } if today['innate'].is_a?(Hash)

        out.uniq { |kind, what, _text| [ kind, what ] }
      end

      def cast_entry(spell, rank, charclass, how = nil)
        suffix = ''
        suffix += "/rank #{rank}" if rank && rank.to_s != 'cantrip' && how.nil?
        suffix += "/class #{charclass}" if charclass
        suffix += "/#{how}" if how
        way = Acting.way_needed(spell, [])
        suffix += "/#{way.args['ways'].split(', ').first.downcase}" if way.err?
        label = how ? "#{spell} (#{how})" : spell

        if healing?(spell)
          [ :heal, label, -> { "e/cast #{spell}=#{hurt_ally.name}#{suffix}" } ]
        elsif fighting?(spell)
          [ :spell, label, -> { "e/cast #{spell}=#{foe_ref.call}#{suffix}" } ]
        else
          [ :spell, label, "e/cast #{spell}#{suffix}" ]
        end
      end

      # ------------------------------------------------------------------------------
      # Between encounters, and after

      def rest!
        say '## The GM rests the party'
        type(@gm, 'e/rest')
      end

      def wrap_up!
        say '## After'
        @party.each do |char|
          type(char, 'sheet')
          type(char, 'gear')
        end
      end

      def run!
        stage!
        build_party!
        outfit!

        first = fight!(@waves[0])
        second = @waves[1] ? fight!(@waves[1], carries_on: first) : nil

        wrap_up!
        [ first, second ].compact
      end

      # ------------------------------------------------------------------------------
      # What it found

      def errors
        @outcomes.select(&:error)
      end

      # Per player, everything they tried and how it went, the first time they tried it.
      def coverage
        @party.each_with_object({}) do |char, out|
          out[char.name] = @tries.select { |one| one.who == char.name }
                                 .uniq { |one| [ one.kind, one.what ] }
                                 .map { |one| [ one.kind, one.what, one.outcome.status ] }
        end
      end

      def report
        lines = [ "# #{@name}", '' ]

        coverage.each_pair do |who, rows|
          ok = rows.count { |_kind, _what, status| status == 'ok' }
          lines << "## #{who}: #{ok}/#{rows.size} ok"
          rows.each { |kind, what, status| lines << "- #{kind} #{what}: #{status}" }
          lines << ''
        end

        lines << '## Errors'
        errors.each { |one| lines << "- #{one.who}: #{one.text} -> #{one.status}" }
        lines << ''
        lines << '## Interactions'
        @probes.each { |name, status| lines << "- #{name}: #{status}" }
        lines << ''
        lines << "## Arithmetic: #{@audit.counts.map { |what, count| "#{count} #{what}" }.join(', ')}"
        @audit.findings.each { |one| lines << "- #{one}" }
        lines.join("\n")
      end

      def cleanup!
        @encounters.each { |one| PF2Encounter[one.id]&.delete }
        @party.each { |char| Character[char.id]&.delete }
        [ @gm, @staff, @scene, @room ].compact.uniq(&:id).each { |one| one.class[one.id]&.delete }
      end
    end
  end
end
