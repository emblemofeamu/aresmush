module AresMUSH
  module Pf2e
    module Chargen

      # Setting the base information a character is built from: ancestry, heritage,
      # background, class, specialty and the faith trio.
      #
      # Pure. Every config read goes through state['config'], every failure is an Err with a
      # code the specs branch on, and the only thing that changes is the returned state -
      # nothing is written and nothing is granted. Chargen picks become ledger grants when
      # the stage is committed, which is also why changing class here cannot leave the old
      # class's features behind the way writing them immediately did.
      module BaseInfo

        ELEMENTS = %w{ancestry background charclass heritage specialize deity alignment specialize_info sanctification}.freeze

        # Deities whose followers cannot be champions.
        UNHOLY_DEITIES = [ 'Caracoroth', 'Deimos', 'Gunahkar', 'Illotha', 'Maugrim', 'Taara', 'Thul' ].freeze

        def self.set(state, args)
          element = ELEMENTS.find { |e| e.include?(args['element'].to_s) }

          return Err.new(:bad_element, 'pf2e.bad_element', 'invalid' => args['element'], 'options' => ELEMENTS.join(", ")) unless element

          options = options_for(state, element)

          return options if options.is_a?(Err)

          value = resolve(options, args['value'])

          return value if value.is_a?(Err)

          check = cross_checks(state, element, value)

          return check if check.is_a?(Err)

          apply(state, element, value)
        end

        # ------------------------------------------------------------------------------
        # What may be chosen
        # ------------------------------------------------------------------------------

        def self.options_for(state, element)
          config = state['config']
          base = state['base_info']

          case element
          when 'heritage'
            ancestry = base['ancestry']
            return Err.new(:ancestry_not_set, 'pf2e.ancestry_not_set') if ancestry.blank?
            Array(config.read('pf2e_ancestry', ancestry, 'heritages')).sort
          when 'specialize'
            charclass = base['charclass']
            return Err.new(:charclass_not_set, 'pf2e.charclass_not_set') if charclass.blank?
            (config.read('pf2e_specialty', charclass) || {}).keys.sort
          when 'specialize_info'
            charclass = base['charclass']
            specialty = base['specialize']
            return Err.new(:specialty_not_set, 'pf2e.specialty_not_set') if specialty.blank?

            choose = (config.read('pf2e_specialty', charclass, specialty) || {})['choose']
            return Err.new(:specialty_no_info, 'pf2e.specialty_no_info') if choose.nil?

            (choose['options'] || {}).keys.sort
          when 'deity'
            (config.read('pf2e_deities') || {}).keys.sort
          when 'alignment'
            Array(config.read('pf2e', 'allowed_alignments'))
          when 'sanctification'
            charclass = base['charclass']
            return Err.new(:charclass_not_set, 'pf2e.charclass_not_set') if charclass.blank?
            return Err.new(:sanctification_wrong_class, 'pf2e.sanctification_wrong_class') unless uses_sanctification?(charclass)

            deity = state['faith']['deity']
            return Err.new(:sanctification_needs_deity, 'pf2e.sanctification_needs_deity') if charclass.casecmp?('Cleric') && deity.blank?

            sanctification_options(state, charclass, deity, base['specialize'])
          when 'charclass'
            (config.read('pf2e_class') || {}).keys.sort
          else
            (config.read("pf2e_#{element}") || {}).keys.sort
          end
        end

        # Substring match, the way the command has always worked: "khaz" finds Khazad, and an
        # ambiguous fragment is refused rather than guessed at.
        def self.resolve(options, value)
          wanted = value.to_s.downcase

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'option', 'options' => options.join(", ")) if wanted.empty?

          exact = options.find { |o| o.to_s.casecmp?(value.to_s) }

          return exact if exact

          matches = options.select { |o| o.to_s.downcase.include?(wanted) }

          return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'option', 'options' => options.join(", ")) if matches.empty?
          return Err.new(:multiple_matches, 'pf2e.multiple_matches', 'element' => value) if matches.size > 1

          matches.first
        end

        def self.uses_sanctification?(charclass)
          return false if charclass.blank?

          charclass.casecmp?('Cleric') || charclass.casecmp?('Champion')
        end

        def self.sanctification_options(state, charclass, deity, specialize)
          config = state['config']

          return [] if charclass.blank?

          if charclass.casecmp?('Cleric')
            return [] if deity.blank?
            Array(config.read('pf2e_deities', deity, 'allowed_sanctifications'))
          elsif charclass.casecmp?('Champion')
            if !specialize.blank?
              from_specialty = (config.read('pf2e_specialty', 'Champion', specialize) || {})['allowed_sanctifications']
              return from_specialty if from_specialty
            end

            Array(config.read('pf2e_class', 'Champion', 'allowed_sanctifications'))
          else
            []
          end
        end

        # ------------------------------------------------------------------------------
        # Cross-checks between the choices already made
        # ------------------------------------------------------------------------------

        def self.cross_checks(state, element, value)
          config = state['config']
          base = state['base_info']
          faith = state['faith']

          if element == 'charclass' && value.casecmp?('Champion') && UNHOLY_DEITIES.include?(faith['deity'])
            return Err.new(:champion_deity_mismatch, 'pf2e.cg_champion_deity_mismatch', 'deity' => faith['deity'])
          end

          if config.read('pf2e', 'use_alignment') && [ 'deity', 'alignment' ].include?(element)
            alignment = element == 'alignment' ? value : faith['alignment']
            deity = element == 'deity' ? value : faith['deity']

            if !alignment.blank? && !deity.blank?
              allowed = Array(config.read('pf2e_deities', deity, 'allowed_alignments'))

              unless allowed.include?(alignment)
                return Err.new(:deity_alignment_mismatch, 'pf2e.cg_deity_alignment_mismatch', 'deity' => deity, 'options' => allowed.join(", "))
              end
            end
          end

          if config.read('pf2e', 'use_alignment') && base['charclass'].to_s.casecmp?('Champion') && [ 'specialize', 'alignment', 'deity' ].include?(element)
            specialty = element == 'specialize' ? value : base['specialize']
            alignment = element == 'alignment' ? value : faith['alignment']

            if !specialty.blank?
              allowed = Array((config.read('pf2e_specialty', 'Champion', specialty) || {})['allowed_alignments'])

              if !alignment.blank? && !allowed.empty? && !allowed.include?(alignment)
                return Err.new(:champion_specialty_alignment_mismatch, 'pf2e.cg_champion_specialty_alignment_mismatch', 'specialty' => specialty, 'options' => allowed.join(", "))
              end
            end
          end

          if element == 'sanctification'
            allowed = sanctification_options(state, base['charclass'], faith['deity'], base['specialize'])

            unless allowed.include?(value)
              return Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'sanctification', 'options' => allowed.join(", "))
            end
          end

          nil
        end

        # ------------------------------------------------------------------------------
        # The transformation
        # ------------------------------------------------------------------------------

        def self.apply(state, element, value)
          base = state['base_info'].dup
          faith = state['faith'].dup

          case element
          when 'ancestry'
            base['ancestry'] = value
            base['heritage'] = ''
          when 'charclass'
            base['charclass'] = value
            base['specialize'] = ''
            base['specialize_info'] = ''
            faith['sanctification'] = '' unless uses_sanctification?(value)
          when 'specialize'
            base['specialize'] = value
            base['specialize_info'] = ''
          when 'heritage', 'background', 'specialize_info'
            base[element] = value
          when 'deity', 'alignment', 'sanctification'
            faith[element] = value
          end

          outcome = Ok.new(:state => state.merge('base_info' => base, 'faith' => faith))
            .with_message('pf2e.option_set', 'element' => element, 'option' => value)

          hints(outcome, state, element, value)
        end

        # The friendly follow-ups the command has always printed: what to pick next.
        def self.hints(outcome, state, element, value)
          config = state['config']

          case element
          when 'ancestry'
            heritages = Array(config.read('pf2e_ancestry', value, 'heritages')).sort
            return outcome if heritages.empty?
            ooc(outcome, 'pf2e.cg_ancestry_heritages', 'ancestry' => value, 'heritages' => heritages.join(", "))
          when 'charclass'
            specialties = (config.read('pf2e_specialty', value) || {}).keys.sort
            result = specialties.empty? ? outcome : ooc(outcome, 'pf2e.cg_charclass_specializations', 'class' => value, 'specializations' => specialties.join(", "))
            return ooc(result, 'pf2e.cg_champion_sanctificationnotice') if value.casecmp?('Champion')
            return ooc(result, 'pf2e.cg_cleric_sanctificationnotice') if value.casecmp?('Cleric')
            result
          when 'specialize'
            choose = (config.read('pf2e_specialty', state['base_info']['charclass'], value) || {})['choose'] || {}
            options = (choose['options'] || {}).keys.sort
            return outcome if options.empty?
            ooc(outcome, 'pf2e.cg_specialty_info_required', 'specialty' => value, 'class' => state['base_info']['charclass'], 'options' => options.join(", "))
          else
            outcome
          end
        end

        def self.ooc(outcome, key, args = {})
          Ok.new(
            :state => outcome.state,
            :grants => outcome.grants,
            :messages => outcome.messages + [ { 'key' => key, 'args' => args, 'type' => 'ooc' } ]
          )
        end
      end
    end
  end
end
