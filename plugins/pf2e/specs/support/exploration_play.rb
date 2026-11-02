module AresMUSH
  module Pf2e

    # An adventure played in a scene, the way a table plays one: the GM starts a scene and sets it, the
    # party poses in, explores, fights, explores again and recovers, fights again, and the GM stops the
    # scene. Every step is a command someone types - `scene/start`, `pose`, `+e/explore`, `+e/act scout`,
    # `+e/start` - and the scene's own log is read back afterwards for what it kept.
    module ExplorationPlay

      # What each seat does as the party travels: what a player of that class would choose.
      def activity_for(char)
        state = state_of(char)
        charclass = Character[char.id].pf2_base_info['charclass']

        return 'Defend' if state.shields.to_a.any?(&:equipped) && !ShieldBlock.cannot_raise(state)
        return 'Avoid Notice' if %w{Rogue Swashbuckler Investigator}.include?(charclass)
        return 'Scout' if %w{Ranger Monk Barbarian}.include?(charclass)
        return 'Detect Magic' if Pf2emagic.is_caster?(Character[char.id])

        'Search'
      end

      def adventure!(fights)
        stage_scene!
        build_party!
        outfit!

        @party.each { |char| type(char, "pose arrives with the others, #{Character[char.id].pf2_base_info['charclass'].downcase} kit in hand.") }

        explore!
        first = fight!(fights[0], from_exploration: true)
        explore!(from: first, recovering: true)
        second = fight!(fights[1], from_exploration: true)

        finish!
        [ first, second ]
      end

      # A room for the adventure, and the scene in it, started the way a GM starts one.
      def stage_scene!
        @room = Room.create(:name => "#{@name} Road #{rand(1000000)}", :room_type => 'IC')
        @gm = Character.create(:name => "Gm#{rand(1000000)}", :room => @room)
        Roles.add_role(@gm, 'approved')
        @gm = Character[@gm.id]
        @staff = @gm

        say "# #{@name}: a party of #{@seats.size} at level #{@level}, in a scene"
        say ''
        type(@gm, 'scene/start')
        @scene = Room[@room.id].scene

        raise "#{@name}: the GM could not start a scene" unless @scene

        # The running game shares this database, and its empty-scene cleanup (:15 and :45 past each hour)
        # stops a scene in an ordinary room nobody is connected to. A temporary room's scene it leaves for
        # days, so a play-through long enough to cross the hour keeps its scene.
        @scene.update(:temp_room => true)

        type(@gm, "scene/title #{@name}")
        type(@gm, 'emit/set A muddy road winds toward the ruins; something has been dragging carcasses along it.')
        say ''
      end

      # An exploration: carrying on from the fight before it, if there was one. Each player joins, says
      # what they are doing, poses and makes a check; recovering, the party treats its wounds and
      # refocuses.
      def explore!(from: nil, recovering: false)
        say "## Exploring#{from ? " after encounter #{from.id}" : ''}"

        started = type(@gm, from ? "e/explore=#{from.id}" : 'e/explore')
        @encounter = PF2Encounter.scene_active_encounter(Scene[@scene.id])

        raise unstarted('an exploration', started) unless @encounter

        @encounters << @encounter
        @explorations << @encounter

        @party.each do |char|
          type(char, 'e/join')
          type(char, "pose #{recovering ? 'catches their breath' : 'moves on'}, watching the treeline.")
          type(char, "e/act #{activity_for(char).downcase}")
        end

        # What their class gives them to do only while exploring - an investigator's Pursue a Lead.
        @party.each do |char|
          exploring_only(char).each { |action| attempt(char, :explore, action, "e/act #{action.downcase}") }
        end

        type(@gm, 'e/view')
        @party.each { |char| type(char, 'roll perception/20') }

        recover! if recovering

        type(@gm, 'emit The tracks end at a breach in the old wall. Something moves inside.')
        say ''
      end

      def exploring_only(char)
        own_actions(char, state_of(char)).select do |action|
          Exploration.only_exploring?(action, Actions.info(action)) && !Exploration.activity?(action) &&
            !Actions.info(action)['check']
        end
      end

      # The party patches itself up: whoever is best at Medicine treats each of the wounded, and anyone
      # with a focus pool short of full refocuses.
      def recover!
        medic = @party.max_by { |char| Pf2e.prof_rank(Pf2eSkills.get_skill_prof(state_of(char), 'Medicine').to_s.downcase).to_i }

        @party.select { |char| hp_of(char) < max_hp_of(char) }.each do |hurt|
          attempt(medic, :explore, "Treat Wounds on #{hurt.name}", "e/act treat wounds=#{hurt.name}")
        end

        @party.each do |char|
          magic = state_of(char).magic
          next unless magic && Pf2emagic.focus_pool_max(magic).to_i > Pf2emagic.focus_points_left(magic).to_i

          attempt(char, :explore, 'Refocus', 'e/refocus')
        end

        type(@gm, 'e/view')
      end

      # The party poses out, and the GM stops the scene.
      def finish!
        say '## Finish'
        @party.each { |char| type(char, 'pose wipes their blade clean and looks back the way they came.') }
        type(@gm, 'emit The ruins fall quiet.')
        type(@gm, 'scene/stop')
        say ''
      end

      # ------------------------------------------------------------------------------
      # What the scene kept

      def scene_poses
        Scene[@scene.id].scene_poses.to_a.sort_by { |pose| pose.id.to_i }
      end

      # The scene's log as a reader of it sees it.
      def scene_log
        scene_poses.map do |pose|
          who = pose.is_system_pose? ? 'system' : pose.character&.name
          kind = [ pose.is_ooc ? 'ooc' : nil, pose.is_setpose ? 'set' : nil ].compact.join(',')

          "[#{who}#{kind.empty? ? '' : " #{kind}"}] #{clean(pose.pose)}"
        end.join("\n")
      end

      # The encounter's bookkeeping, and the lines that tell what happened.
      BOOKKEEPING = /\*\*\* EXPLORING|ENCOUNTER STARTED|END OF ENCOUNTER|joins the exploration|joins encounter|rolls \w+ for initiative|NEW ROUND|Initiative advances|exploration \(encounter \d+\) ends/
      STORY = /strikes|\buses\b|\bcasts\b|Damage to|is exploring:|regains|is now|is no longer/

      # The log the scene keeps once it is shared, which leaves its OOC lines out.
      def shared_log
        Scenes.build_log_text(Scene[@scene.id])
      end

      # What the scene's log should hold, and what it should not.
      def scene_checks!
        poses = scene_poses
        text = poses.map { |pose| clean(pose.pose) }
        # A game line is kept marked with the system prefix, and as told beside it.
        told = poses.map { |pose| clean(pose.system_text.to_s) }
        scene = Scene[@scene.id]

        @audit.counts['scene lines checked'] += poses.size
        @audit.find('scene', 'scene', 'it is still running after scene/stop') unless scene.completed

        @encounters.each do |one|
          encounter = PF2Encounter[one.id]
          @audit.find('scene', "encounter #{one.id}", 'still running after its scene stopped') if encounter.is_active

          EncounterLog.lines(encounter).each do |_time, message|
            next if text.include?(clean(message)) || told.include?(clean(message))

            @audit.find('scene', "encounter #{one.id}", "its line is not in the scene log: #{clean(message)[0, 120]}")
          end
        end

        # A line the GM alone was told - a creature's hit points - which the room never heard. The room
        # hears its lines with a prefix, and may hear the same words on their own account: an effect the
        # GM was told ended as the fight began can end again on a later turn, in front of everyone.
        (@told_gm.uniq - @told_room).each do |line|
          next if @told_room.any? { |heard| heard.include?(line) }
          next unless text.any? { |pose| pose.include?(line) } && line.length > 12

          @audit.find('scene', 'GM only', "a line only the GM was told is in the scene log: #{line[0, 120]}")
        end

        # Bookkeeping is OOC, which the shared log leaves out; what happened is not, so it stays.
        poses.each do |pose|
          shown = clean(pose.pose)
          @audit.find('scene', 'wording', shown[0, 160]) if shown.match?(ScenarioRunner::LEAKS)

          next unless pose.is_system_pose?

          if shown.match?(BOOKKEEPING)
            @audit.find('scene', 'bookkeeping', "kept in the shared log: #{shown[0, 120]}") unless pose.is_ooc
          elsif shown.match?(STORY)
            @audit.find('scene', 'story', "left out of the shared log: #{shown[0, 120]}") if pose.is_ooc
          end
        end

        shared = shared_log
        @audit.find('scene', 'shared log', 'holds no Strike') unless shared.include?('strikes')
        @audit.find('scene', 'shared log', 'holds the bookkeeping') if shared.match?(BOOKKEEPING)
        @party.each do |char|
          @audit.find('scene', 'shared log', "holds none of #{char.name}'s poses") unless shared.include?(char.name)
        end

        @party.each do |char|
          next if poses.any? { |pose| pose.character&.id == char.id && !pose.is_ooc }

          @audit.find('scene', char.name, 'none of their poses is in the scene log')
        end

        order = [ 'EXPLORING', 'ENCOUNTER STARTED', 'END OF ENCOUNTER', 'EXPLORING', 'ENCOUNTER STARTED' ]
        positions = []
        order.each do |marker|
          found = text.each_index.find { |i| text[i].include?(marker) && (positions.empty? || i > positions.last) }
          positions << found if found
        end
        @audit.find('scene', 'order', "phases out of order or missing: #{positions.inspect}") unless positions.size == order.size
      end
    end
  end
end
