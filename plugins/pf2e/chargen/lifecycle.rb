module AresMUSH
  module Pf2e
    module Chargen

      # The chargen stage machine: committing a stage, rewinding to an earlier one, and the
      # confirmation dance in front of a full reset.
      #
      # Every *decision* here is pure and tested - is this stage next, is base info complete,
      # what is missing, may this be rewound. The heavy effects of a commit (building the
      # skill rows, HP and magic from config) still run in the legacy lock helpers, which the
      # command calls after this core has said yes.
      module Lifecycle

        # The stages, in order, and the lock each one closes behind it.
        #
        # A lock is not state of its own: it says the character has passed that stage, which the
        # order already says. Committing and rewinding each used to set the three booleans by hand,
        # three `if`s apiece, and a stage added to the list without its three lines would have left a
        # lock stuck.
        STAGES = [
          { 'name' => 'start', 'lock' => nil },
          { 'name' => 'info', 'lock' => 'baseinfo' },
          { 'name' => 'abilities', 'lock' => 'abilities' },
          { 'name' => 'skills', 'lock' => 'skills' },
          # Feats come after skills and have no stage of their own to lock; `commit featskills` is
          # how the skills lock goes back on after a feat handed over a skill the character had.
          { 'name' => 'featskills', 'lock' => nil }
        ].freeze

        # One exception to the derivation, and it is real: a feat that grants a skill the character is
        # already trained in gives them a free one instead, which reopens the skills lock in the
        # middle of a stage. `commit featskills` closes it again. So the locks a *position* implies are
        # what this answers; a lock toggled by that path is not a position at all.

        CHECKPOINTS = STAGES.map { |stage| stage['name'] }.freeze

        def self.stage_at(name)
          CHECKPOINTS.index(name.to_s)
        end

        # The locks a character standing at this stage holds: every stage up to and including it is
        # closed, and everything after it is open.
        def self.locks_at(checkpoint)
          reached = stage_at(checkpoint)

          STAGES.each_with_object({}) do |stage, locks|
            next unless stage['lock']

            locks[stage['lock']] = !reached.nil? && stage_at(stage['name']) <= reached
          end
        end

        def self.commit(state, args)
          stage = args['stage'].to_s

          return Err.new(:not_in_chargen, 'pf2e.only_in_chargen') if state['chargen_stage'].nil? || state['approved']

          index = CHECKPOINTS.index(stage)

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'commit', 'options' => (CHECKPOINTS - [ 'start' ]).join(", ")) if index.nil? || stage == 'start'
          return Err.new(:wrong_stage, 'pf2e.wrong_stage') unless CHECKPOINTS[index - 1] == state['checkpoint']

          if stage == 'info'
            missing = missing_base_info(state)

            # `missing` stays as locale stems, which is what a spec asserts on; `msg` is what the
            # player reads. Joined unrendered, the failure told them "missing_subclass_info".
            unless missing.empty?
              stem_args = missing_args(state)

              return Err.new(:incomplete, 'pf2e.cg_commit_failed',
                             'msg' => missing.map { |stem| t("pf2e.#{stem}", **(stem_args[stem] || {})) }.join(" "),
                             'missing' => missing, 'option' => stage)
            end
          end

          Ok.new(:state => state.merge('checkpoint' => stage, 'locks' => state['locks'].merge(locks_at(stage))))
            .with_message('pf2e.chargen_committed')
        end

        def self.restore(state, args)
          checkpoint = args['checkpoint'].to_s
          restorable = %w(info abilities skills)

          return Err.new(:bad_option, 'pf2e.cg_restore_help') unless restorable.include?(checkpoint)

          current = CHECKPOINTS.index(state['checkpoint'])
          target = CHECKPOINTS.index(checkpoint)

          return Err.new(:bad_option, 'pf2e.cg_restore_help') if current.nil?
          return Err.new(:stage_not_reached, 'pf2e.cg_cant_restore_to_stage_you_dont_have', 'checkpoint' => checkpoint) if current < target

          # Rewinding to a stage reopens it and everything after it, so the character stands at the
          # stage before it - with that stage's locks, and with it as the next thing to commit.
          standing = CHECKPOINTS[target - 1]

          Ok.new(:state => state.merge('checkpoint' => standing, 'locks' => state['locks'].merge(locks_at(standing))))
            .with_message('pf2e.cg_restore_ok', 'checkpoint' => checkpoint)
        end

        # Two-step confirmation, kept as data: the first bare call arms the reset, the second
        # with confirm goes ahead. do_reset tells the shell to run the destructive part.
        def self.reset(state, args)
          confirm = !!args['confirm']
          pending = !!state['reset_pending']

          if pending && !confirm
            return Ok.new(:state => state).with_message('pf2e.must_confirm')
          elsif !pending && confirm
            return Err.new(:reset_first, 'pf2e.reset_first')
          elsif !pending && !confirm
            return Ok.new(:state => state.merge('reset_pending' => true)).with_message('pf2e.are_you_sure')
          end

          Ok.new(:state => state.merge('reset_pending' => false, 'do_reset' => true))
            .with_message('pf2e.cg_reset_ok')
        end

        # ------------------------------------------------------------------------------
        # What is still missing before base info can be locked
        # ------------------------------------------------------------------------------

        # Returns locale key *stems* rather than rendered text, so a spec can assert on
        # 'missing_heritage' without a translation table. A stem that takes arguments carries
        # them in the second element of the pair `missing_args` returns.
        def self.missing_base_info(state)
          base = state['base_info']
          faith = state['faith']
          charclass = base['charclass']
          specialize = base['specialize']
          missing = []

          missing << 'missing_ancestry' if base['ancestry'].blank?
          missing << 'missing_heritage' if !base['ancestry'].blank? && base['heritage'].blank?
          missing << 'missing_background' if base['background'].blank?
          missing << 'missing_charclass' if charclass.blank?
          missing << 'missing_alignment' if faith['alignment'].blank?
          missing << 'missing_subclass' if needs_specialty?(state, charclass) && specialize.blank?
          missing << 'missing_subclass_info' if needs_specialty_choice?(state, charclass, specialize) && base['specialize_info'].blank?

          if needs_deity?(state, charclass) || background_needs_deity?(state, base['background'])
            missing << 'missing_deity' if faith['deity'].blank?
          end

          if BaseInfo.uses_sanctification?(charclass)
            options = BaseInfo.sanctification_options(state, charclass, faith['deity'], specialize)

            if faith['sanctification'].blank?
              missing << 'missing_sanctification'
            elsif !options.empty? && !options.include?(faith['sanctification'])
              missing << 'sanctification_invalid'
            end
          end

          missing
        end

        # What each stem needs to render. Only one of them takes anything, and rendering it
        # without its options put a literal %{options} in front of the player.
        def self.missing_args(state)
          base = state['base_info']
          charclass = base['charclass']

          return {} unless BaseInfo.uses_sanctification?(charclass)

          options = BaseInfo.sanctification_options(state, charclass, state['faith']['deity'], base['specialize'])

          { 'sanctification_invalid' => { :options => options.sort.join(", ") } }
        end

        def self.needs_specialty?(state, charclass)
          return false if charclass.blank?

          (state['config'].read('pf2e', 'subclass_names') || {}).key?(charclass)
        end

        def self.needs_specialty_choice?(state, charclass, specialize)
          return false if charclass.blank? || specialize.blank?

          info = state['config'].read('pf2e_specialty', charclass, specialize)

          info ? info.key?('choose') : false
        end

        def self.needs_deity?(state, charclass)
          return false if charclass.blank?

          !!state['config'].read('pf2e_class', charclass, 'use_deity')
        end

        def self.background_needs_deity?(state, background)
          return false if background.blank?

          !!state['config'].read('pf2e_background', background, 'needs_deity')
        end
      end
    end
  end
end
