module AresMUSH
  module Pf2e

    # Situations a fight should handle, set up by the GM and played by the party at the start of each
    # encounter, each checked once it has happened: the circumstances a player names, conditions an
    # action or a spell leaves and what they do to the next roll, a character dropping and getting back
    # up, and the GM taking a change back. What does not happen as the rules say is a finding.
    #
    # Mixed into `ScenarioRunner`, which supplies the party, the GM, the encounter and the audit.
    module InteractionProbes

      def probe(name)
        say "### Probe: #{name}"
        ok, detail = yield
        @probes << [ name, ok ? 'ok' : "FAILED: #{detail}" ]
        @audit.find('interaction', name, detail) unless ok
      rescue StandardError => e
        @probes << [ name, "ERROR #{e.class}: #{e.message}" ]
        @audit.find('interaction', name, "#{e.class}: #{e.message} (#{e.backtrace&.first})")
      end

      def conditions_of(holder)
        (holder.class[holder.id].pf2_conditions || {})
      end

      def value_of(holder, name)
        held = conditions_of(holder)[name]

        held.is_a?(Hash) ? held['value'].to_i : (held ? 1 : 0)
      end

      # Who makes the probes' Strikes: someone with a weapon who can Strike at all. A restrained one
      # cannot, and a probe would read a defence nobody rolled.
      def martial
        free = able.reject { |char| restrained?(char) }
        free.find { |char| weapon_of(char) } || free.first || @party.first
      end

      def restrained?(char)
        state = state_of(char)
        state && Pf2e.held_conditions(state).key?('Restrained')
      end

      def weapon_of(char)
        state_of(char).weapons.to_a.find(&:equipped)&.name
      end

      def ranged_of(char)
        state_of(char).weapons.to_a.find { |one| one.equipped && one.wp_type == 'ranged' }&.name
      end

      def rows_of(result)
        Array(((result || {})['breakdown'] || {})['modifiers'])
      end

      # The foe a probe acts on, fixed as it starts: the weakest one may die partway through, and what is
      # checked after is what happened to the one acted on.
      # With none left standing, the GM brings in another of the wave's creatures, so every probe has a
      # target.
      def aim
        type(@gm, "e/add #{adding(@wave.first)}") unless foe
        row = foe
        [ "##{row['id']}", Pf2eNpc[row['npc']] ]
      end

      def defence_rows(holder)
        rows_of(@audit.last_defence(holder.name))
      end

      def interactions!
        striker = martial
        weapon = weapon_of(striker)

        probe('standard cover is +2 circumstance to AC') do
          covered, holder = aim
          type(@gm, "e/cover #{covered}=standard")
          struck = type(striker, "e/strike #{covered}=#{weapon}")
          type(@gm, "e/cover #{covered}=none")
          # A Strike refused rolled nothing, and the defence read would be another's.
          next [ false, "the Strike was refused: #{struck.status}" ] unless struck.ok?

          rows = rows_of(@audit.last_defence(holder.name))
          found = rows.find { |row| row['type'] == 'circumstance' && row['value'].to_i == 2 }
          [ found, "no +2 circumstance in #{rows.inspect[0, 300]}" ]
        end

        probe('flanking leaves the target off-guard, -2 circumstance to AC') do
          ref, holder = aim
          struck = type(striker, "e/strike #{ref}=#{weapon}/flanking")
          next [ false, "the Strike was refused: #{struck.status}" ] unless struck.ok?

          found = defence_rows(holder).find { |row| row['type'] == 'circumstance' && row['value'].to_i == -2 }
          [ found, "no -2 circumstance in #{defence_rows(holder).inspect[0, 300]}" ]
        end

        probe('the second Strike of a turn takes the multiple attack penalty') do
          rows = rows_of((@audit.last_roll(striker.name) || {})['result'])
          found = rows.find { |row| [ -4, -5, -8, -10 ].include?(row['value'].to_i) && row['source'].to_s.match?(/attack/i) }
          [ found, "no multiple attack penalty in #{rows.map { |row| [ row['source'], row['value'] ] }.inspect}" ]
        end

        probe('a concealed target makes a Strike roll a DC 5 flat check first') do
          ref, _holder = aim
          type(@gm, "e/conceal #{ref}=concealed")
          type(striker, "e/strike #{ref}=#{weapon}")
          type(@gm, "e/conceal #{ref}=none")
          shown = @lines.last(8).join(' ')
          [ shown.match?(/DC 5|flat/i), "no flat check told: #{shown[0, 300]}" ]
        end

        probe('a hidden target makes a Strike roll a DC 11 flat check first') do
          ref, _holder = aim
          type(@gm, "e/conceal #{ref}=hidden")
          type(striker, "e/strike #{ref}=#{weapon}")
          type(@gm, "e/conceal #{ref}=none")
          shown = @lines.last(8).join(' ')
          [ shown.include?('11'), "no DC 11 flat check told: #{shown[0, 300]}" ]
        end

        probe('a successful Grapple leaves the target grabbed, and grabbed is off-guard') do
          ref, holder = aim
          tried = type(striker, "e/act grapple=#{ref}")
          # Something more than a size larger is not grappled at all.
          next [ tried.failures.first.include?('too large'), "refused: #{tried.failures.first}" ] if tried.failures.any?

          degree = (@audit.last_roll(striker.name) || {}).dig('result', 'degree').to_i
          held = conditions_of(holder)
          wanted = { 3 => 'Restrained', 2 => 'Grabbed' }[degree]

          # A swarm, among others, is never held, whatever was rolled.
          next [ !held.key?(wanted), "an immune target was left #{wanted}" ] if wanted && Pf2e.immune_to?(holder, wanted)
          next [ !held.key?('Grabbed'), "degree #{degree} left it grabbed" ] unless wanted
          next [ false, "degree #{degree} should leave it #{wanted}, holds #{held.keys}" ] unless held.key?(wanted)
          next [ true, nil ] if holder.class[holder.id].hp_left.zero?

          type(striker, "e/strike #{ref}=#{weapon}")
          found = defence_rows(holder).find { |row| row['type'] == 'circumstance' && row['value'].to_i == -2 }
          [ found, "a #{wanted.downcase} target is not off-guard: #{defence_rows(holder).inspect[0, 300]}" ]
        end

        archer = able.find { |char| ranged_of(char) }
        if archer
          probe('the third range increment is -4 to the attack') do
            ref, _holder = aim
            type(archer, 'e/reload') if Loading.held(state_of(archer)).any?
            shot = type(archer, "e/strike #{ref}=#{ranged_of(archer)}/range 3")
            # A Strike that was refused rolled nothing, and the last roll is someone else's business.
            next [ false, "refused: #{shot.failures.first}" ] if shot.failures.any?

            rows = rows_of((@audit.last_roll(archer.name) || {})['result'])
            [ rows.any? { |row| row['value'].to_i == -4 && row['source'].to_s.include?('range') }, "no -4 range penalty in #{rows.map { |row| [ row['source'], row['value'] ] }.inspect}" ]
          end
        end

        demoralizer = (able.any? ? able : @party).max_by { |char| Pf2eSkills.get_skill_bonus(Character[char.id], 'Intimidation').to_i rescue 0 }
        probe('Demoralize leaves Frightened by its degree, which then lowers the target\'s DCs') do
          ref, holder = aim
          before = value_of(holder, 'Frightened')
          type(demoralizer, "e/act demoralize=#{ref}")
          degree = (@audit.last_roll(demoralizer.name) || {}).dig('result', 'degree')
          wanted = { 3 => 2, 2 => 1 }.fetch(degree, 0)
          now = value_of(holder, 'Frightened')

          # The mindless and the fearless are untouched by it, whatever would have been rolled.
          if IWR.immune_to_effect?(IWR.for(holder), Actions.info('Demoralize')['traits']) || Pf2e.immune_to?(holder, 'Frightened')
            next [ now == before, "an immune target went from Frightened #{before} to #{now}" ]
          end

          next [ true, nil ] if wanted.zero? && now == before
          next [ false, "degree #{degree} should leave Frightened #{wanted}, holds #{now}" ] unless now == [ wanted, before ].max
          next [ true, nil ] if holder.class[holder.id].hp_left.zero?

          type(striker, "e/strike #{ref}=#{weapon}")
          found = defence_rows(holder).find { |row| row['type'] == 'status' && row['value'].to_i == -now }
          [ found, "Frightened #{now} not on its AC: #{defence_rows(holder).inspect[0, 300]}" ]
        end

        probe('the GM takes a condition back with +e/undo, and puts it back with +e/redo') do
          ref, holder = aim
          type(striker, "e/act demoralize=#{ref}")
          held = conditions_of(holder).keys.sort
          type(@gm, 'e/undo')
          undone = conditions_of(holder).keys.sort
          type(@gm, 'e/redo')
          redone = conditions_of(holder).keys.sort
          [ redone == held, "held #{held}, after undo #{undone}, after redo #{redone}" ]
        end

        probe('a successful Trip leaves the target prone, and prone is off-guard') do
          ref, holder = aim
          tried = type(striker, "e/act trip=#{ref}")
          next [ tried.failures.first.include?('too large'), "refused: #{tried.failures.first}" ] if tried.failures.any?

          degree = (@audit.last_roll(striker.name) || {}).dig('result', 'degree')
          prone = conditions_of(holder).key?('Prone')

          # A swarm, among others, is never knocked down, whatever was rolled.
          next [ !prone, "an immune target was left prone" ] if Pf2e.immune_to?(holder, 'Prone')
          next [ !prone, "degree #{degree} left it prone" ] unless degree.to_i >= 2
          next [ false, "degree #{degree} did not leave it prone" ] unless prone
          next [ true, nil ] if holder.class[holder.id].hp_left.zero?

          type(striker, "e/strike #{ref}=#{weapon}")
          found = defence_rows(holder).find { |row| row['type'] == 'circumstance' && row['value'].to_i == -2 }
          [ found, "prone target is not off-guard: #{defence_rows(holder).inspect[0, 300]}" ]
        end

        rogue = able.find { |char| Character[char.id].pf2_base_info['charclass'] == 'Rogue' }
        if rogue
          probe('a rogue\'s Strike at an off-guard target adds sneak attack\'s precision damage') do
            ref, _holder = aim
            hit = 4.times.find do
              @audit.instance_variable_set(:@last_damage, nil)
              type(rogue, "e/strike #{ref}=#{weapon_of(rogue) || 'fist'}/flanking")
              @audit.last_damage
            end

            next [ true, nil ] unless hit

            rows = @audit.last_damage
            [ rows.any? { |row| row['category'] == 'precision' }, "no precision damage in #{rows.inspect[0, 300]}" ]
          end
        end

        barbarian = able.find { |char| Character[char.id].pf2_base_info['charclass'] == 'Barbarian' }
        if barbarian
          probe('Rage gives temporary hit points and adds its damage to a melee Strike') do
            type(barbarian, 'e/act rage')
            state = state_of(barbarian)
            melee = state.weapons.to_a.find { |one| one.equipped && one.wp_type != 'ranged' }
            attack = Pf2eCombat.attack_descriptor(state, melee)
            sources = Damage.of(state, attack)['instances'].flat_map { |one| one['sources'] }

            [ state.temp_hp.to_i.positive? && sources.any? { |one| one.to_s.match?(/rage/i) },
              "temporary hit points #{state.temp_hp}, damage from #{sources.inspect}" ]
          end
        end

        # A shield broken in an earlier fight gives nothing raised, and is refused; it is no test.
        shield = able.find { |char| state_of(char).shields.to_a.any?(&:equipped) && !ShieldBlock.cannot_raise(state_of(char)) }
        if shield
          probe('Raise a Shield is +2 circumstance to AC against the next Strike') do
            aim

            # A restrained creature makes no Strike to read, and the Grapple probe can leave one so.
            free = foes.find { |row| !Pf2e.held_conditions(Pf2eNpc[row['npc']]).key?('Restrained') }
            next [ true, nil ] unless free

            raised = type(shield, 'e/act raise a shield')
            next [ false, "Raise a Shield was refused: #{raised.status}" ] unless raised.ok?

            struck = type(@gm, "e/as ##{free['id']}=strike #{shield.name}")
            next [ false, "the creature's Strike was refused: #{struck.status}" ] unless struck.ok?

            rows = rows_of(@audit.last_defence(shield.name))
            [ rows.any? { |row| row['type'] == 'circumstance' && row['value'].to_i == 2 }, "no +2 circumstance: #{rows.inspect[0, 300]}" ]
          end
        end

        blessed = @party.last
        probe('Bless is +1 status to the attack of whoever it is on') do
          ref, _holder = aim
          type(@gm, "effect/add #{blessed.name}=bless")
          struck = type(blessed, "e/strike #{ref}=#{weapon_of(blessed) || 'fist'}")

          # Someone restrained, or inside what they would strike at, makes no Strike to read.
          next [ true, nil ] unless struck.ok?

          rows = rows_of((@audit.last_roll(blessed.name) || {})['result'])
          [ rows.any? { |row| row['type'] == 'status' && row['value'].to_i == 1 }, "no +1 status: #{rows.map { |row| [ row['source'], row['type'], row['value'] ] }.inspect}" ]
        end

        helper = @party.first
        healed = @party[2]
        carries = lambda do |char|
          state_of(char).consumables.to_a.index { |one| one.name.start_with?('Healing Potion') && one.quantity.to_i.positive? }
        end

        # A GM trusted to gives a potion out; under any other, whoever still carries one spends it.
        type(@gm, "e/loot #{helper.name}=Healing Potion (Minor)") if Character[@gm.id].has_permission?('trusted_gm')
        helper = ([ helper ] + @party - [ healed ]).find { |char| carries.call(char) && able.include?(char) }

        if helper
          probe('a potion given to a dying ally ends their dying, and leaves them wounded and awake') do
            # The fight may have downed them already, and nothing more happens to the dead. They go from
            # standing to dying here, so that it is this damage and this potion being checked.
            rescue_the_fallen if down?(healed)
            type(@gm, "condition/set #{healed.name}=wounded/0") if value_of(state_of(healed), 'Wounded').positive?
            type(@gm, "damage #{healed.name}=#{hp_of(healed)}")
            dying = value_of(state_of(healed), 'Dying')
            type(helper, "e/use consumables=#{carries.call(helper)}/#{healed.name}")
            held = conditions_of(state_of(healed))

            [ dying.positive? && !held.key?('Dying') && !held.key?('Unconscious') && value_of(state_of(healed), 'Wounded') >= 1 &&
                hp_of(healed).positive?,
              "dying #{dying}; after the potion #{held.keys}, #{hp_of(healed)} hit points" ]
          end
        end

        # A night's rest restores Constitution times level, at least level, and ends what a fight left.
        probe('the GM\'s rest restores a night\'s hit points and clears what the fight left') do
          # Nothing more happens to the dead, so they are brought back. Someone alive at 0 stays there, and
          # the night has to get them up.
          @party.each do |char|
            next unless Pf2e.dead?(state_of(char))

            raise_if_dead(char)
            type(@gm, "condition/set #{char.name}=dying/0")
          end

          before = @party.to_h { |char| [ char.name, hp_of(char) ] }
          type(@gm, 'e/rest')
          wrong = @party.filter_map do |char|
            con = Pf2eAbilities.abilmod(Pf2eAbilities.get_score(Character[char.id], 'Constitution'))
            wanted = [ before[char.name] + [ con, 1 ].max * Character[char.id].pf2_level.to_i, max_hp_of(char) ].min
            "#{char.name} #{before[char.name]} -> #{hp_of(char)}, not #{wanted}" unless hp_of(char) == wanted
          end
          lingering = @party.select { |char| (conditions_of(state_of(char)).keys & %w{Dying Unconscious Frightened}).any? }.map(&:name)

          [ wrong.empty? && lingering.empty?, "#{wrong.join('; ')}; still under conditions: #{lingering}" ]
        end

        dropped = @party[1]
        probe('a character brought to 0 is dying, and healed is wounded') do
          # Unwounded, so that going to nothing is Dying 1 and neither death nor being spared it.
          type(@gm, "condition/set #{dropped.name}=wounded/0") if value_of(state_of(dropped), 'Wounded').positive?
          type(@gm, "damage #{dropped.name}=#{hp_of(dropped)}")
          dying = value_of(state_of(dropped), 'Dying')
          type(@gm, "heal #{dropped.name}=#{max_hp_of(dropped)}")
          wounded = value_of(state_of(dropped), 'Wounded')
          still = value_of(state_of(dropped), 'Dying')
          [ dying >= 1 && still.zero? && wounded >= 1, "dying #{dying} at 0, then dying #{still} and wounded #{wounded} once healed" ]
        end
      end

      # ------------------------------------------------------------------------------
      # Checked after every command of the fight

      # A spell cast at a foe leaves what its outcome says on it.
      def spell_outcome!(caster, text)
        spell = text[/\Ae\/cast ([^=\/]+)/, 1].to_s.strip
        target_ref = text[/=(#\d+)/, 1]

        return unless target_ref

        mechanics = Acting.spell_mechanics(spell).last

        return unless mechanics && (mechanics['outcomes'] || {}).any?
        # With no save or attack the cast rolls nothing, and the last roll is from something else.
        return unless mechanics['attack'] || mechanics['save']

        row = Combatants.rows(encounter).find { |one| "##{one['id']}" == target_ref }
        holder = row && Combatants.holder_of(row)

        return unless holder

        save = @audit.last_roll(holder.name)
        attack = @audit.last_roll(caster.name)
        result = mechanics['attack'] ? attack && attack['result'] : save && save['result']

        return unless result && result['degree']
        # A target immune to the spell is passed by, and rolls nothing new to read.
        return if IWR.immune_to_effect?(IWR.for(holder), mechanics['traits'], DamageAbout.spell(spell))

        wanted = Array((mechanics['outcomes'] || {})[Degree::NAMES[result['degree']]]).select { |one| one['condition'] }
                 .reject { |one| Pf2e.immune_to?(holder, Pf2e.canonical_condition(one['condition'])) }
        held = conditions_of(holder)

        wanted.each do |one|
          @audit.counts['spell outcomes checked'] += 1
          name = Pf2e.canonical_condition(one['condition'])
          value = held[name].is_a?(Hash) ? held[name]['value'].to_i : (held[name] ? 1 : 0)

          next if held.key?(name) && value >= one['value'].to_i

          @audit.find('auto condition', "#{caster.name} cast #{spell} at #{holder.name}",
                      "#{Degree::NAMES[result['degree']]} should leave #{name} #{one['value']}, holds #{held.keys.inspect}")
        end
      end

      # A character whose turn starts while dying rolls a recovery check.
      def recovery_rolled!(told)
        holder = frightened_before_turn_ends&.first

        return unless holder && !Actors.of(holder).creature?

        @audit.counts['turns checked for dying'] += 1
        rolled = told.any? { |line| line.include?('recovery check') }
        # The dead roll nothing.
        dying_now = value_of(holder, 'Dying').positive? && !Pf2e.dead?(holder.class[holder.id])

        return if rolled || !dying_now

        @audit.find('auto condition', "#{holder.name}'s turn started dying", 'no recovery check was rolled')
      end

      # Frightened eases by one at the end of its holder's turn.
      def frightened_before_turn_ends
        name = ActiveEffects.current_turn(encounter)
        row = Combatants.rows(encounter).find { |one| one['name'] == name }
        holder = row && Combatants.holder_of(row)

        holder ? [ holder, value_of(holder, 'Frightened') ] : nil
      end

      def frightened_eased!(held)
        return unless held && held.last.positive?

        holder, before = held
        now = value_of(holder, 'Frightened')
        @audit.counts['frightened turns checked'] += 1

        return if now == before - 1

        @audit.find('auto condition', "#{holder.name}'s turn ended", "Frightened #{before} should ease to #{before - 1}, is #{now}")
      end
    end
  end
end
