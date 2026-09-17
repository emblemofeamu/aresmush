module AresMUSH
  module Pf2e

    # Drives a character from a blank sheet to a target level through the real commands,
    # satisfying whatever each level asks for. Used by the :dbtest walkthrough specs, and by
    # `rake pf2e:build[Class,level]` for exploring a class by hand.
    #
    # It deliberately keeps builds simple - no dedications, and feats without follow-up
    # choices where one is available - so a failure means the level ladder is broken rather
    # than that the builder made an exotic choice.
    class AutoBuilder

      # Records what a command said instead of writing to a socket.
      class CaptureClient
        attr_reader :successes, :failures, :oocs

        def initialize
          @successes = []
          @failures = []
          @oocs = []
        end

        def logged_in?; true; end
        def screen_reader; false; end
        def char; nil; end
        def width; 80; end
        def emit_success(msg); @successes << msg.to_s; end
        def emit_failure(msg); @failures << msg.to_s; end
        def emit_ooc(msg); @oocs << msg.to_s; end
        def emit(msg); @successes << msg.to_s; end
        def to_s; "AutoBuilder"; end
        def clear; @successes = []; @failures = []; @oocs = []; end

        # The driver script called these; kept as aliases so the extracted resolver reads
        # unchanged.
        alias_method :fails, :failures
        alias_method :oks, :successes
      end

      PLUGINS = [ 'Pf2e', 'Pf2emagic', 'Pf2egear', 'Pf2noms' ].freeze

      attr_reader :char, :client, :notes

      def initialize(char, trace: false)
        @char = char
        @client = CaptureClient.new
        @trace = trace
        @notes = []
        @picked_spells = []
      end

      def note(msg)
        @notes << msg
        puts "  #{msg}" if @trace
      end

      def failures
        @client.failures
      end

      def clear
        @client.clear
      end

      def run(text)
        before = @client.failures.size
        cmd = Command.new(text)
        handler = PLUGINS.lazy.map { |name| (AresMUSH.const_get(name).get_cmd_handler(@client, cmd, @char) rescue nil) }.find { |h| h }

        raise "no handler for #{text}" unless handler

        handler.new(@client, cmd, @char).on_command
        @char = Character[@char.id]
        note "rejected: #{text} -> #{@client.failures.last}" if @trace && @client.failures.size > before
        @char
      end

      def all_skills
        @@all_skills ||= Pf2e.easter_scrub(Global.read_config('pf2e_skills').keys)
      end

      # Picks a feat that keeps the build simple: no follow-up choice, no grants that spawn new
      # requirements, and never a dedication (which drags in a whole archetype).
      def feat_pick(type)
        options = (Pf2e.get_feat_options(@char, type) rescue [])

        ranked = options.reject do |f|
          d = Global.read_config('pf2e_feats', f) || {}
          types = Array(d['feat_type']).map(&:to_s)
          types.include?('Dedication') || types.include?('Archetype') || d.key?('assoc_archetype')
        end

        simple = ranked.find do |f|
          d = Global.read_config('pf2e_feats', f) || {}
          !d.key?('feat_choice') && !d.key?('grants') && !d.key?('init_magic')
        end

        simple || ranked.first || options.first
      end

      def lore_pick
        lores = Global.read_config('pf2e_skills').keys.select { |s| s.include?('Lore') }
        trained = @char.skills.to_a.reject { |sk| sk.prof_level == 'untrained' }.map(&:name)
        Pf2e.easter_scrub(lores).find { |l| !trained.include?(l) }
      end

      def all_spells
        # All five pf2e_spells_*.yml files merge into one pf2e_spells section.
        @@all_spells ||= (Global.read_config('pf2e_spells') || {})
      end

      TRADITIONS = [ 'arcane', 'divine', 'occult', 'primal' ].freeze

      # The tradition a caster actually casts from. The class config carries it for classes with a
      # fixed tradition; for bloodline/patron/mystery casters it only appears on the magic object,
      # where `tradition` is keyed by *class name* with the tradition inside the value.
      def tradition_for(klass)
        chargen = Global.read_config('pf2e_class', klass, 'chargen') || {}
        from_config = ((chargen['magic_stats'] || {})['tradition'] || {}).keys.find { |k| TRADITIONS.include?(k.to_s.downcase) }
        return from_config if from_config

        magic = @char.magic
        return nil unless magic

        magic.tradition.each_pair do |key, value|
          next if key.to_s == 'innate'
          return key.to_s.downcase if TRADITIONS.include?(key.to_s.downcase)
          found = Array(value).map(&:to_s).map(&:downcase).find { |v| TRADITIONS.include?(v) }
          return found if found
        end

        nil
      end

      # A legal, not-yet-known spell of the given rank ('cantrip' or a number) for this caster.
      def highest_castable_rank
        [ ((@char.pf2_level + 1) / 2), 1 ].max
      end

      # Curriculum / restricted spells eligible at this rank, if the class restricts any slots.
      def restricted_candidates(rank_key, klass)
        magic = @char.magic
        return [] unless magic

        level = rank_key.to_s == 'any' ? highest_castable_rank : rank_key
        out = []

        [ (magic.restricted_spellbook || {})[klass], Pf2emagic.advancement_restricted_spellbook(@char, klass) ].compact.each do |for_class|
          next unless for_class.is_a?(Hash)
          for_class.each_key do |restriction|
            list = (Pf2emagic.restricted_spell_list(@char, klass, restriction, level) rescue [])
            out.concat(Array(list).map(&:to_s))
          end
        end

        out.uniq - spells_known
      rescue
        []
      end

      def spell_candidates(rank_key, klass)
        restricted_candidates(rank_key, klass) + spell_pool(rank_key, klass)
      end

      def spell_pool(rank_key, klass)
        trad = tradition_for(klass)
        known = spells_known
        wanted_cantrip = rank_key.to_s == 'cantrip'
        rank = rank_key.to_s == 'any' ? highest_castable_rank : rank_key.to_i

        all_spells.select do |name, info|
          next false unless info.is_a?(Hash)
          next false if known.include?(name)
          traits = Array(info['traits'])
          next false unless trad.nil? || Array(info['tradition']).include?(trad)
          if wanted_cantrip
            traits.include?('cantrip')
          else
            !traits.include?('cantrip') && info['base_level'].to_i == rank
          end
        end.keys
      end

      def spell_pick(rank_key, klass)
        trad = tradition_for(klass)
        known = spells_known
        wanted_cantrip = rank_key.to_s == 'cantrip'
        rank = rank_key.to_s == 'any' ? highest_castable_rank : rank_key.to_i

        all_spells.each_pair do |name, info|
          next unless info.is_a?(Hash)
          next if known.include?(name)
          traits = Array(info['traits'])
          trads = Array(info['tradition'])
          next unless trad.nil? || trads.include?(trad)
          if wanted_cantrip
            next unless traits.include?('cantrip')
          else
            next if traits.include?('cantrip')
            next unless info['base_level'].to_i == rank
          end
          return name
        end
        nil
      end

      @picked_spells = []

      # Everything already chosen: on the magic object, staged in to_assign, or sent this run.
      def spells_known
        known = @picked_spells.dup
        magic = @char.magic
        if magic
          known.concat(magic.spellbook.values.flatten.compact.map(&:to_s)) rescue nil
          known.concat(magic.repertoire.values.flatten.compact.map(&:to_s)) rescue nil
        end
        [ 'spellbook', 'repertoire' ].each do |key|
          slots = (@char.pf2_to_assign || {})[key]
          next unless slots.is_a?(Hash)
          slots.each_value { |list| known.concat(Array(list).reject { |v| v == 'open' }.map(&:to_s)) }
        end
        known.uniq
      end

      def untrained_pick
        trained = @char.skills.to_a.reject { |sk| sk.prof_level == 'untrained' }.map(&:name)
        all_skills.reject { |s| s.include?('Lore') }.find { |s| !trained.include?(s) }
      end

      # Fills whatever the character currently has outstanding. Returns commands run.
      KNOWN_KEYS = [
        'bg skill choice','class skill choice','specialty skill choice','bgskill','open skills','open languages',
        'feats','raise skill','raise skill choice','raise ability','languages','charclass_feature option',
        'spellbook','repertoire','signature','archetype_deity','archetype_sanctification','grants','innate','repertoire_swap',
        'class option','archetype','feat choice'
      ]

      # Resolving a choice is `cg/option` during chargen and `advance/option` afterwards; the wrong
      # one fails the `check_advancing` guard and the choice stays open.
      def option_cmd(context)
        context == :chargen ? 'cg/option' : 'advance/option'
      end

      # Spending a feat slot is `cg/feat` during chargen and `advance/feat` afterwards. The slot
      # pool is the same one either side.
      def feat_cmd(context)
        context == :chargen ? 'cg/feat' : 'advance/feat'
      end

      def resolve_outstanding(context)
        runs = 0
        ta = @char.pf2_to_assign || {}

        [['bg skill choice','bgchoice'], ['class skill choice','classchoice'], ['specialty skill choice','specialtychoice']].each do |key, type|
          slot = ta[key]
          next unless slot.is_a?(Hash) && (slot['selected'].nil? || slot['selected'] == 'open')
          pick = Array(slot['options']).find { |o| all_skills.include?(o) } || Array(slot['options']).first
          next unless pick
          run("skill/set #{type}=#{pick}"); runs += 1
        end

        if ta['bgskill'].is_a?(Array)
          run("skill/set background=#{ta['bgskill'].first}"); runs += 1
        end

        Array(ta['open skills']).count('open').times do
          pick = untrained_pick
          break unless pick
          run("skill/set free=#{pick}"); runs += 1
        end

        langs = Global.read_config('pf2e_languages', 'common').keys
        Array(ta['open languages']).count('open').times do
          pick = langs.find { |l| !@char.pf2_lang.include?(l) }
          break unless pick
          run("lang/set #{pick}"); runs += 1
        end

        Array(ta['languages']).count('open').times do
          pick = langs.find { |l| !@char.pf2_lang.include?(l) }
          break unless pick
          run("advance/language=#{pick}"); runs += 1
        end

        # Feat slots, the same pool either side of approval. Which command spends one differs:
        # cg/feat during chargen, advance/feat afterwards.
        if ta['feats'].is_a?(Hash)
          ta['feats'].each_pair do |type, slots|
            Array(slots).count('open').times do
              pick = feat_pick(type)
              if !pick
                note "!! no #{type} feat options at level #{@char.pf2_level}"
                break
              end
              run("#{feat_cmd(context)} #{type}=#{pick}"); runs += 1
            end
          end
        end

        # Skill increases. A slot can ask for an untrained skill specifically.
        Array(ta['raise skill']).count('open untrained').times do
          pick = untrained_pick
          break unless pick
          run("advance/raise skill=#{pick}"); runs += 1
        end

        Array(ta['raise skill']).count('open').times do
          current = @char.skills.to_a.reject { |sk| sk.prof_level == 'untrained' }
          level = @char.pf2_level
          cap = level >= 15 ? 'master' : (level >= 7 ? 'expert' : 'expert')
          pick = current.find { |sk| sk.prof_level == 'trained' } || current.find { |sk| sk.prof_level == 'expert' && level >= 7 }
          if !pick
            pick_name = untrained_pick
            break unless pick_name
            run("advance/raise skill=#{pick_name}"); runs += 1
          else
            run("advance/raise skill=#{pick.name}"); runs += 1
          end
        end

        if ta['raise skill choice'].is_a?(Hash)
          opts = Array(ta['raise skill choice']['options'])
          pick = opts.first
          if pick then run("advance/raise skill=#{pick}"); runs += 1 end
        end

        # Ability boosts arrive as a set; the command wants them in one comma list.
        if ta['raise ability']
          slots = Array(ta['raise ability'])
          open_count = slots.count('open')
          if open_count > 0
            abilities = @char.abilities.to_a.sort_by { |a| a.base_val }.reverse.map(&:name)
            picks = abilities.first(open_count)
            run("advance/raise ability=#{picks.join(', ')}"); runs += 1
          end
        end

        # Class feature choices ('class option' during advancement).
        [ 'class option', 'charclass_feature option' ].each do |key|
          next unless ta[key].is_a?(Hash)

          ta[key].each_pair do |feature, data|
            # A resolved choice is stored as the chosen string, so there is nothing to do.
            next if data.is_a?(String)

            options = Pf2e::Advancement::Options.option_list(data)
            next if options.empty?

            selected = data.is_a?(Hash) ? data['selected'] : nil
            next if selected && selected != 'open'

            # The first option is not always legal - a Monk's Second Path to Perfection has
            # to be a save they did not already take - so try them until one is accepted.
            accepted = options.find do |option|
              before = @client.fails.size
              run("#{option_cmd(context)} #{feature}=#{option}")
              @client.fails.size == before
            end

            if accepted
              runs += 1
            else
              note "!! no option accepted for #{feature.inspect} (tried #{options.inspect}): #{@client.fails.last}"
            end
          end
        end

        if ta['feat choice'].is_a?(Hash)
          ta['feat choice'].each_pair do |name, slots|
            next unless Array(slots).include?('open')

            block = (Pf2e.find_choice_block(@char, name) rescue nil)

            # The game can enumerate a choice block's legal options, including 'from' and
            # 'from_feats' blocks whose options are computed rather than listed.
            options = begin
              block ? Array(Pf2e.choice_options(@char, name, block)) : []
            rescue StandardError => e
              # Noted rather than swallowed: a raise here is usually a bug in the game, not here.
              note "!! choice_options raised for #{name.inspect}: #{e.class}: #{e.message}"
              []
            end
            pick = options.first
            pick ||= Array(block && block['options']).first
            pick ||= lore_pick if name.to_s.downcase.include?('lore')

            if !pick
              note "!! cannot resolve feat choice #{name.inspect} (block keys: #{block ? block.keys.inspect : 'nil'})"
              next
            end

            run("#{option_cmd(context)} #{name}=#{pick}"); runs += 1
          end
        end

        klass = @char.pf2_base_info['charclass']

        [ 'spellbook', 'repertoire' ].each do |key|
          slots = ta[key]
          next unless slots.is_a?(Hash)
          note "SHAPE #{key}: #{slots.inspect[0,200]}" if @trace

          # Both lists may arrive keyed by class first ({'Bard' => {'cantrip' => [...]}}),
          # which is how a character with more than one casting class is kept apart.
          slots = slots[klass] if slots[klass].is_a?(Hash)
          next unless slots.is_a?(Hash)

          slots.each_pair do |rank_key, list|
            Array(list).count('open').times do
              candidates = spell_candidates(rank_key, klass).first(40)
              accepted = false

              candidates.each do |pick|
                before = @client.fails.size

                if context == :chargen
                  lvl = rank_key.to_s == 'cantrip' ? 0 : (rank_key.to_s == 'any' ? highest_castable_rank : rank_key.to_i)
                  run("addspell #{klass}/#{lvl}=#{pick}")
                else
                  rank_arg = rank_key.to_s == 'any' ? highest_castable_rank : rank_key
                  run("advance/spell #{key}/#{klass}/#{rank_arg}=#{pick}")
                  still_open = Array(((@char.pf2_to_assign || {})[key] || {})[rank_key]).count('open')
                  run("advance/spell #{key}/#{rank_arg}=#{pick}") if still_open > 0
                end

                remaining = Array(((@char.pf2_to_assign || {})[key] || {})[rank_key]).count('open')

                if @client.fails.size == before && remaining < Array(list).count('open')
                  @picked_spells << pick
                  accepted = true
                  runs += 1
                  break
                end
              end

              if !accepted
                note "!! no #{key} spell accepted for rank #{rank_key} (tried #{candidates.size}; pool=#{spell_pool(rank_key, klass).size} all=#{all_spells.size} trad=#{tradition_for(klass).inspect} known=#{spells_known.size})"
                break
              end
            end
          end
        end

        # Signature spells are chosen from the repertoire, including the spells picked
        # earlier in this same advancement - which is why this runs after the loop above and
        # reads the preview rather than the saved repertoire.
        if ta['signature'].is_a?(Hash)
          signature = ta['signature']
          signature = signature[klass] if signature[klass].is_a?(Hash)

          signature.each_pair do |rank_key, list|
            Array(list).count('open').times do
              repertoire = (Pf2e.preview_repertoire(@char, klass) rescue {})[klass] || {}
              known = Array(repertoire[rank_key.to_s]).compact.reject { |sp| sp.to_s.casecmp?('open') }

              # A spell already taken as a signature at this rank cannot be taken again.
              taken = Array(((@char.pf2_to_assign || {})['signature'] || {})[rank_key])
              taken = Array((((@char.pf2_to_assign || {})['signature'] || {})[klass] || {})[rank_key]) if taken.empty?

              candidates = known.reject { |sp| taken.any? { |t| t.to_s.casecmp?(sp.to_s) } }

              accepted = candidates.find do |pick|
                before = @client.fails.size
                run("advance/spell signature/#{klass}/#{rank_key}=#{pick}")
                @client.fails.size == before
              end

              if accepted
                runs += 1
              else
                note "!! no signature spell accepted at rank #{rank_key} (repertoire=#{known.inspect[0, 120]}): #{@client.fails.last}"
                break
              end
            end
          end
        end

        unknown = ta.keys.reject { |k| KNOWN_KEYS.include?(k) }
        note "?? unhandled to_assign keys: #{unknown.inspect}" unless unknown.empty?

        runs
      end

      # ------------------------------------------------------------------------------
      # The build itself
      # ------------------------------------------------------------------------------

      # Chargen: base info, the four commits, boosts, skills, languages and feats.
      def build_level_one(charclass)
        @char.update(:chargen_stage => 4)
        Pf2eAbilities.factory_default(@char)
        Pf2eSkills.factory_default(@char)
        @char = Character[@char.id]

        run "cg/set ancestry=Khazad"
        run "cg/set heritage=Forge"
        run "cg/set background=Acolyte"
        run "cg/set charclass=#{charclass}"

        # A specialty can constrain alignment (champion causes do), so pick the pair together.
        specialties = Global.read_config('pf2e_specialty', charclass) || {}
        alignment = 'BL'
        specialty = specialties.keys.find do |name|
          allowed = Array((specialties[name] || {})['allowed_alignments'])
          allowed.empty? || allowed.include?(alignment)
        end

        if specialties.any? && specialty.nil?
          specialty = specialties.keys.first
          alignment = Array((specialties[specialty] || {})['allowed_alignments']).first || alignment
        end

        run "cg/set alignment=#{alignment}"

        if specialty
          run "cg/set specialize=#{specialty}"
          choose = (specialties[specialty] || {})['choose']
          option = choose ? (choose['options'] || {}).keys.first : nil
          run "cg/set specialize_info=#{option}" if option
        end

        run "cg/set deity=Althea" if Global.read_config('pf2e_class', charclass, 'use_deity')

        if Pf2e.uses_sanctification?(charclass)
          sanctifications = Pf2e.allowed_sanctifications(charclass, @char.pf2_faith['deity'], @char.pf2_base_info['specialize'])
          run "cg/set sanctification=#{sanctifications.first}" if sanctifications.first
        end

        run "commit info"
        assign_boosts
        run "commit abilities"
        3.times { break if resolve_outstanding(:chargen).zero? }
        run "commit skills"
        3.times { break if resolve_outstanding(:chargen).zero? }
        run "commit featskills" if outstanding_free_skill?

        @char
      end

      def assign_boosts
        abilities = @char.abilities.to_a.map(&:name)

        @char.pf2_boosts_working.each_pair do |type, slots|
          next unless slots.is_a?(Array)

          slots.each_with_index do |slot, _i|
            next unless slot == 'open' || slot.is_a?(Array)

            taken = @char.pf2_boosts_working[type].select { |s| s.is_a?(String) && s != 'open' }
            choices = slot.is_a?(Array) ? slot : abilities
            pick = choices.find { |a| !taken.include?(a) }
            next unless pick

            run "boost/set #{type}=#{pick}"
          end
        end
      end

      def outstanding_free_skill?
        Array((@char.pf2_to_assign || {})['open skills']).include?('open')
      end

      # Grants the XP and approval a climb needs, then advances one level at a time.
      def advance_to(target)
        # Approving a character normally fires CharApprovedEvent, whose handler commits the
        # chargen draft to the ledger. Adding the role directly skips the event, so the
        # commit is done here to match what a real approval does.
        unless @char.is_approved?
          Roles.add_role(@char, 'approved')
          @char = Character[@char.id]
          Pf2e::Ledger.commit_chargen!(@char)
        end

        Pf2e.award_xp(@char, (target + 2) * 1000, 'AutoBuilder', 'level build')
        @char = Character[@char.id]

        ((@char.pf2_level + 1)..target).each do |level|
          clear
          run "advance"

          if !failures.empty?
            note "level #{level}: advance refused - #{failures.first}"
            break
          end

          6.times { break if resolve_outstanding(:advance).zero? }

          clear
          run "advance/done"

          if !failures.empty?
            note "level #{level}: advance/done refused - #{failures.first}"
            note "  outstanding: #{@char.pf2_to_assign.inspect[0, 300]}"
            break
          end
        end

        @char
      end

      def build(charclass, target)
        build_level_one(charclass)
        advance_to(target) if target > 1
        @char
      end

      # What the finished sheet holds, in the shape the specs assert on.
      def summary
        {
          'level' => @char.pf2_level,
          'xp' => @char.pf2_xp,
          # Through DraftSheet, because a pick made before the draft commits is in the draft rather
          # than on the sheet, and a summary taken mid-chargen has to count it.
          'feats' => Pf2e::DraftSheet.of(@char).feats_by_bucket.transform_values { |v| Array(v).size },
          'skills' => @char.skills.to_a.reject { |s| s.prof_level == 'untrained' }.group_by(&:prof_level).transform_values(&:size),
          'languages' => Array(@char.pf2_lang).size,
          'grants' => @char.grants.count
        }
      end

    end
  end
end
