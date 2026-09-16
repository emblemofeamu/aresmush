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

        CHECKPOINTS = %w(start info abilities skills featskills).freeze

        def self.commit(state, args)
          stage = args['stage'].to_s

          return Err.new(:not_in_chargen, 'pf2e.only_in_chargen') if state['chargen_stage'].to_i.zero? || state['approved']

          index = CHECKPOINTS.index(stage)

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'commit', 'options' => (CHECKPOINTS - [ 'start' ]).join(", ")) if index.nil? || stage == 'start'
          return Err.new(:wrong_stage, 'pf2e.wrong_stage') unless CHECKPOINTS[index - 1] == state['checkpoint']

          if stage == 'info'
            missing = missing_base_info(state)

            return Err.new(:incomplete, 'pf2e.cg_commit_failed', 'msg' => missing.join(", "), 'option' => stage) unless missing.empty?
          end

          locks = state['locks'].dup
          locks['baseinfo'] = true if stage == 'info'
          locks['abilities'] = true if stage == 'abilities'
          locks['skills'] = true if stage == 'skills'

          Ok.new(:state => state.merge('checkpoint' => stage, 'locks' => locks))
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

          locks = state['locks'].dup
          locks['skills'] = false if target <= CHECKPOINTS.index('skills')
          locks['abilities'] = false if target <= CHECKPOINTS.index('abilities')
          locks['baseinfo'] = false if target <= CHECKPOINTS.index('info')

          Ok.new(:state => state.merge('checkpoint' => checkpoint, 'locks' => locks))
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

        # Returns locale key *stems* rather than rendered text: the command joins and renders
        # them, and a spec can assert on 'missing_heritage' without a translation table.
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
