module AresMUSH
  module Pf2e
    module Chargen

      # Setting the base information a character is built from: ancestry, heritage,
      # background, class, specialty and the faith trio.
      #
      # Each element is one row in ELEMENTS. A row says where the value is stored, what it
      # clears when it changes, where its legal options come from, what must already be set
      # before it can be chosen, and what to tell the player afterwards. Adding an element is
      # adding a row - there is no case statement to keep in step.
      #
      # Pure: every config read goes through state['config'], every failure is an Err with a
      # code the specs branch on, and the only thing that changes is the returned state.
      # Chargen picks become ledger grants when the stage is committed, not here.
      module BaseInfo

        # Deities whose followers cannot be champions.
        UNHOLY_DEITIES = [ 'Caracoroth', 'Deimos', 'Gunahkar', 'Illotha', 'Maugrim', 'Taara', 'Thul' ].freeze

        # A prerequisite: the field that must be set, and the error if it is not.
        NEEDS_ANCESTRY = { 'store' => 'base_info', 'field' => 'ancestry', 'code' => :ancestry_not_set, 'key' => 'pf2e.ancestry_not_set' }.freeze
        NEEDS_CLASS = { 'store' => 'base_info', 'field' => 'charclass', 'code' => :charclass_not_set, 'key' => 'pf2e.charclass_not_set' }.freeze
        NEEDS_SPECIALTY = { 'store' => 'base_info', 'field' => 'specialize', 'code' => :specialty_not_set, 'key' => 'pf2e.specialty_not_set' }.freeze

        ELEMENTS = {
          'ancestry' => {
            'store' => 'base_info',
            'clears' => [ 'heritage' ],
            'options' => lambda { |state| (state['config'].read('pf2e_ancestry') || {}).keys.sort },
            'hints' => lambda { |state, value|
              heritages = Array(state['config'].read('pf2e_ancestry', value, 'heritages')).sort
              heritages.empty? ? [] : [ [ 'pf2e.cg_ancestry_heritages', { 'ancestry' => value, 'heritages' => heritages.join(", ") } ] ]
            }
          },
          'heritage' => {
            'store' => 'base_info',
            'needs' => [ NEEDS_ANCESTRY ],
            'options' => lambda { |state| Array(state['config'].read('pf2e_ancestry', state['base_info']['ancestry'], 'heritages')).sort }
          },
          'background' => {
            'store' => 'base_info',
            'options' => lambda { |state| (state['config'].read('pf2e_background') || {}).keys.sort }
          },
          'charclass' => {
            'store' => 'base_info',
            'clears' => [ 'specialize', 'specialize_info' ],
            'options' => lambda { |state| (state['config'].read('pf2e_class') || {}).keys.sort },
            'hints' => lambda { |state, value|
              out = []
              specialties = (state['config'].read('pf2e_specialty', value) || {}).keys.sort
              out << [ 'pf2e.cg_charclass_specializations', { 'class' => value, 'specializations' => specialties.join(", ") } ] unless specialties.empty?
              out << [ 'pf2e.cg_champion_sanctificationnotice', {} ] if value.casecmp?('Champion')
              out << [ 'pf2e.cg_cleric_sanctificationnotice', {} ] if value.casecmp?('Cleric')
              out
            }
          },
          'specialize' => {
            'store' => 'base_info',
            'clears' => [ 'specialize_info' ],
            'needs' => [ NEEDS_CLASS ],
            'options' => lambda { |state| (state['config'].read('pf2e_specialty', state['base_info']['charclass']) || {}).keys.sort },
            'hints' => lambda { |state, value|
              charclass = state['base_info']['charclass']
              choose = (state['config'].read('pf2e_specialty', charclass, value) || {})['choose'] || {}
              options = (choose['options'] || {}).keys.sort
              options.empty? ? [] : [ [ 'pf2e.cg_specialty_info_required', { 'specialty' => value, 'class' => charclass, 'options' => options.join(", ") } ] ]
            }
          },
          'specialize_info' => {
            'store' => 'base_info',
            'needs' => [ NEEDS_CLASS, NEEDS_SPECIALTY ],
            'options' => lambda { |state|
              charclass = state['base_info']['charclass']
              choose = (state['config'].read('pf2e_specialty', charclass, state['base_info']['specialize']) || {})['choose']

              next Err.new(:specialty_no_info, 'pf2e.specialty_no_info') if choose.nil?

              (choose['options'] || {}).keys.sort
            }
          },
          'deity' => {
            'store' => 'faith',
            'options' => lambda { |state| (state['config'].read('pf2e_deities') || {}).keys.sort }
          },
          'alignment' => {
            'store' => 'faith',
            'options' => lambda { |state| Array(state['config'].read('pf2e', 'allowed_alignments')) }
          },
          'sanctification' => {
            'store' => 'faith',
            'needs' => [ NEEDS_CLASS ],
            'options' => lambda { |state|
              charclass = state['base_info']['charclass']

              next Err.new(:sanctification_wrong_class, 'pf2e.sanctification_wrong_class') unless BaseInfo.uses_sanctification?(charclass)

              deity = state['faith']['deity']

              next Err.new(:sanctification_needs_deity, 'pf2e.sanctification_needs_deity') if charclass.casecmp?('Cleric') && deity.blank?

              BaseInfo.sanctification_options(state, charclass, deity, state['base_info']['specialize'])
            }
          }
        }.freeze

        # Cross-checks that involve more than one already-made choice. Each returns nil or an
        # Err; they run in order for whichever elements they watch.
        CROSS_CHECKS = [
          {
            'elements' => [ 'charclass' ],
            'check' => lambda { |state, _element, value|
              next nil unless value.casecmp?('Champion') && UNHOLY_DEITIES.include?(state['faith']['deity'])

              Err.new(:champion_deity_mismatch, 'pf2e.cg_champion_deity_mismatch', 'deity' => state['faith']['deity'])
            }
          },
          {
            'elements' => [ 'deity', 'alignment' ],
            'check' => lambda { |state, element, value|
              next nil unless state['config'].read('pf2e', 'use_alignment')

              alignment = element == 'alignment' ? value : state['faith']['alignment']
              deity = element == 'deity' ? value : state['faith']['deity']

              next nil if alignment.blank? || deity.blank?

              allowed = Array(state['config'].read('pf2e_deities', deity, 'allowed_alignments'))

              next nil if allowed.include?(alignment)

              Err.new(:deity_alignment_mismatch, 'pf2e.cg_deity_alignment_mismatch', 'deity' => deity, 'options' => allowed.join(", "))
            }
          },
          {
            # cg/info offers the intersection of what the base list, the class, the cause and the
            # deity allow; setting has to enforce the same set. Only Champion restricts at class
            # level, and its causes narrow it further - but a character picks a class before a
            # cause, so without this the class's own restriction went unchecked.
            'elements' => [ 'charclass', 'alignment' ],
            'check' => lambda { |state, element, value|
              next nil unless state['config'].read('pf2e', 'use_alignment')

              charclass = element == 'charclass' ? value : state['base_info']['charclass']
              alignment = element == 'alignment' ? value : state['faith']['alignment']

              next nil if charclass.blank? || alignment.blank?

              allowed = Array((state['config'].read('pf2e_class', charclass) || {})['allowed_alignments'])

              next nil if allowed.empty? || allowed.include?(alignment)

              Err.new(:class_alignment_mismatch, 'pf2e.cg_class_alignment_mismatch',
                      'charclass' => charclass, 'options' => allowed.join(", "))
            }
          },
          {
            'elements' => [ 'specialize', 'alignment', 'deity' ],
            'check' => lambda { |state, element, value|
              next nil unless state['config'].read('pf2e', 'use_alignment')
              next nil unless state['base_info']['charclass'].to_s.casecmp?('Champion')

              specialty = element == 'specialize' ? value : state['base_info']['specialize']
              alignment = element == 'alignment' ? value : state['faith']['alignment']

              next nil if specialty.blank? || alignment.blank?

              allowed = Array((state['config'].read('pf2e_specialty', 'Champion', specialty) || {})['allowed_alignments'])

              next nil if allowed.empty? || allowed.include?(alignment)

              Err.new(:champion_specialty_alignment_mismatch, 'pf2e.cg_champion_specialty_alignment_mismatch', 'specialty' => specialty, 'options' => allowed.join(", "))
            }
          },
          {
            'elements' => [ 'sanctification' ],
            'check' => lambda { |state, _element, value|
              allowed = BaseInfo.sanctification_options(state, state['base_info']['charclass'], state['faith']['deity'], state['base_info']['specialize'])

              next nil if allowed.include?(value)

              Err.new(:bad_option, 'pf2e.bad_option', 'element' => 'sanctification', 'options' => allowed.join(", "))
            }
          }
        ].freeze

        def self.set(state, args)
          element = ELEMENTS.keys.find { |e| e.include?(args['element'].to_s) }

          return Err.new(:bad_element, 'pf2e.bad_element', 'invalid' => args['element'], 'options' => ELEMENTS.keys.join(", ")) unless element

          spec = ELEMENTS[element]

          missing = unmet_prerequisite(state, spec)
          return missing if missing

          options = spec['options'].call(state)
          return options if options.is_a?(Err)

          value = resolve(options, args['value'])
          return value if value.is_a?(Err)

          failure = cross_check(state, element, value)
          return failure if failure

          apply(state, element, spec, value)
        end

        def self.unmet_prerequisite(state, spec)
          Array(spec['needs']).each do |need|
            next unless state[need['store']][need['field']].blank?

            return Err.new(need['code'], need['key'])
          end

          nil
        end

        def self.cross_check(state, element, value)
          CROSS_CHECKS.each do |rule|
            next unless rule['elements'].include?(element)

            failure = rule['check'].call(state, element, value)

            return failure if failure
          end

          nil
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

        def self.apply(state, element, spec, value)
          stores = { 'base_info' => state['base_info'].dup, 'faith' => state['faith'].dup }
          target = stores[spec['store']]

          target[element] = value
          Array(spec['clears']).each { |field| stores['base_info'][field] = '' }

          # A class that does not use sanctification cannot keep one.
          stores['faith']['sanctification'] = '' if element == 'charclass' && !uses_sanctification?(value)

          outcome = Ok.new(:state => state.merge('base_info' => stores['base_info'], 'faith' => stores['faith']))
            .with_message('pf2e.option_set', 'element' => element, 'option' => value)

          hints = spec['hints'] ? spec['hints'].call(state, value) : []

          hints.reduce(outcome) { |acc, (key, args)| ooc(acc, key, args) }
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
            unless specialize.blank?
              from_specialty = (config.read('pf2e_specialty', 'Champion', specialize) || {})['allowed_sanctifications']
              return from_specialty if from_specialty
            end

            Array(config.read('pf2e_class', 'Champion', 'allowed_sanctifications'))
          else
            []
          end
        end

        def self.ooc(outcome, key, args = {})
          Ok.new(
            :state => outcome.state,
            :grants => outcome.grants,
            :messages => outcome.messages + [ { 'key' => key, 'args' => args, 'type' => 'ooc' } ],
            :revocations => outcome.revocations
          )
        end
      end
    end
  end
end
