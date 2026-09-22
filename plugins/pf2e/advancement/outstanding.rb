module AresMUSH
  module Pf2e
    module Advancement

      # What a character still has to pick before this level-up can be finished.
      #
      # One pure query over the draft, and it is the gate: `advance/done` refuses while this
      # reports anything, `advance/review` lists it, and `advance/info` describes the parts it can
      # answer for. A key that opens a pick therefore cannot be visible to one of them and
      # invisible to another.
      #
      # Each row in SOURCES is one draft key:
      #
      #   kind     - what to call this family of picks
      #   elements - open picks as { label, options }, for a player to name at advance/info
      #   messages - what the review screen says, as [ locale key, args ] pairs
      #   askable  - whether advance/info can answer for the element by that label. False for a
      #              pick with no list to show, so the command does not offer a label it then
      #              refuses.
      #
      # A row whose `messages` is absent speaks through its elements; one whose `elements` is
      # absent is a pick with nothing to enumerate.
      module Outstanding

        OPEN = 'open'.freeze

        # True when any leaf of a nested spell structure is still an open marker.
        def self.open_leaf?(value)
          case value
          when Hash then value.values.any? { |sub| open_leaf?(sub) }
          when Array then value.any? { |sub| open_leaf?(sub) }
          else value.to_s.casecmp?(OPEN)
          end
        end

        # A key that is either the literal 'open' or a list containing it.
        def self.open_marker?(value)
          Array(value).any? { |entry| entry.to_s.casecmp?(OPEN) } || value.to_s.casecmp?(OPEN)
        end

        def self.skill_tokens(value, &test)
          Array(value.is_a?(Array) ? value : [ value ]).count { |entry| test.call(entry) }
        end

        # The spell keys, which share a shape: either a hash of ranks or a hash of sources each
        # holding a hash of ranks. An archetype's list is named in the message, because a player
        # with two spell lists open needs to know which one this is.
        def self.spell_messages(state, key, archetype_key)
          info = state['to_assign'][key]

          return [] unless open_leaf?(info)

          return [ [ 'pf2e.adv_item_innate_spells', {} ] ] if key == 'innate'

          by_source = info.is_a?(Hash) && info.keys.any? { |k| !Pf2e.level_key?(k) }

          return [ [ 'pf2e.adv_item_spells', { 'options' => key } ] ] unless by_source

          info.select { |_source, value| open_leaf?(value) }.map do |source, _value|
            if archetype_key.call(source)
              [ key == 'spellbook' ? 'pf2e.adv_item_archetype_spellbook' : 'pf2e.adv_item_archetype_repertoire',
                { 'archetype' => source } ]
            else
              [ 'pf2e.adv_item_spells', { 'options' => key } ]
            end
          end
        end

        # A signature spell is owed while any rank's entry is an open marker or a count above zero.
        def self.signature_pending?(info)
          return false unless info.is_a?(Hash)

          ranked = info.keys.any? { |k| !Pf2e.level_key?(k) } ? info.values : [ info ]

          ranked.any? do |by_rank|
            next open_marker?(by_rank) || by_rank.to_i.positive? unless by_rank.is_a?(Hash)

            by_rank.values.any? { |v| v.is_a?(Array) ? open_marker?(v) : v.to_i.positive? }
          end
        end

        SOURCES = [
          # Class feature choices: a resolved one is stored as the chosen string.
          {
            'kind' => 'class_option', 'askable' => true,
            'elements' => lambda { |state|
              # Every slot key, not the first one holding a hash: a level that opens a feature
              # choice under two of the three spellings owes both picks.
              Options::SLOTS.flat_map do |key|
                next [] unless state['to_assign'][key].is_a?(Hash)

                state['to_assign'][key].reject { |_feature, options| options.is_a?(String) }
                  .map { |feature, options| { 'label' => feature, 'options' => Options.option_list(options).sort } }
              end
            },
            'messages' => lambda { |state|
              Outstanding.elements_of('class_option', state).map do |e|
                [ 'pf2e.adv_item_class_option_select',
                  { 'name' => e['label'], 'name_downcase' => e['label'].to_s.downcase } ]
              end
            }
          },
          # Choices opened by a feat, which keep their key once resolved - so an entry counts
          # only while one of its slots is still open. The summary of what may be chosen is the
          # shell's to render, because it depends on the character.
          {
            'kind' => 'feat_choice', 'askable' => true,
            'elements' => lambda { |state|
              (state['to_assign']['feat choice'] || {})
                .select { |_name, slots| open_marker?(slots) }
                .map { |name, _slots| { 'label' => name, 'options' => nil } }
            },
            'messages' => lambda { |state|
              Outstanding.elements_of('feat_choice', state).map do |e|
                [ 'pf2e.adv_item_feat_choice_pending', { 'choice' => e['label'] } ]
              end
            }
          },
          # Feat slots the level handed out, by type.
          {
            'kind' => 'feat', 'askable' => true,
            'elements' => lambda { |state|
              feats = state['to_assign']['feats']

              next [] unless feats.is_a?(Hash)

              feats.select { |_type, slots| open_marker?(slots) }
                .map { |type, _slots| { 'label' => "#{type} feat", 'options' => nil } }
            },
            'messages' => lambda { |state|
              (state['to_assign']['feats'] || {}).select { |_type, slots| open_marker?(slots) }
                .map { |type, _slots| [ 'pf2e.adv_item_feat', { 'value' => type.to_s.gsub('charclass', 'class') } ] }
            }
          },
          # Skill increases. An increase restricted to an untrained skill says so, because the
          # player needs to know why their trained skill was refused.
          {
            'kind' => 'raise_skill', 'askable' => false,
            'elements' => lambda { |state|
              info = state['to_assign']['raise skill']

              next [] unless Outstanding.skill_tokens(info) { |e| Pf2e.open_skill_token?(e) }.positive?

              [ { 'label' => 'raise skill', 'options' => nil } ]
            },
            'messages' => lambda { |state|
              info = state['to_assign']['raise skill']
              open = Outstanding.skill_tokens(info) { |e| Pf2e.open_skill_token?(e) }
              untrained = Outstanding.skill_tokens(info) { |e| Pf2e.untrained_only_token?(e) }
              msg = []

              msg << [ 'pf2e.adv_item_raise', { 'item' => 'skill' } ] if open.positive? && untrained.zero?

              if untrained > 1
                msg << [ 'pf2e.adv_item_raise_untrained_skill_multiple', { 'count' => untrained } ]
              elsif untrained == 1
                msg << [ 'pf2e.adv_item_raise_untrained_skill', {} ]
              end

              msg
            }
          },
          {
            'kind' => 'raise_ability', 'askable' => false,
            'elements' => lambda { |state|
              next [] unless Outstanding.skill_tokens(state['to_assign']['raise ability']) { |e| Pf2e.open_skill_token?(e) }.positive?

              [ { 'label' => 'raise ability', 'options' => nil } ]
            },
            'messages' => lambda { |state|
              Outstanding.elements_of('raise_ability', state).map { |_e| [ 'pf2e.adv_item_raise_ability', {} ] }
            }
          },
          # An increase the level restricted to a named list, which is held as that list until it
          # is taken.
          {
            'kind' => 'raise_skill_choice', 'askable' => false,
            'elements' => lambda { |state|
              info = state['to_assign']['raise skill choice']
              pending = info.is_a?(Array) ? !info.empty? : open_marker?(info)

              pending ? [ { 'label' => 'raise skill choice', 'options' => Array(info) } ] : []
            },
            'messages' => lambda { |state|
              Outstanding.elements_of('raise_skill_choice', state).map { |_e| [ 'pf2e.adv_item_skill_choice', {} ] }
            }
          },
          {
            'kind' => 'language', 'askable' => false,
            'elements' => lambda { |state|
              count = Array(state['to_assign']['open languages']).count { |e| e.to_s.casecmp?(OPEN) }

              count.positive? ? [ { 'label' => 'open languages', 'options' => nil, 'count' => count } ] : []
            },
            'messages' => lambda { |state|
              Outstanding.elements_of('language', state).map { |e| [ 'pf2e.adv_item_language', { 'count' => e['count'] } ] }
            }
          }
        ].freeze

        # The spell lists and signature spells, whose rows are generated because the three spell
        # keys differ only in which message they carry.
        SPELL_KEYS = %w{spellbook repertoire innate}.freeze

        SPELL_SOURCES = SPELL_KEYS.map do |key|
          {
            'kind' => key, 'askable' => false,
            'elements' => lambda { |state|
              Outstanding.open_leaf?(state['to_assign'][key]) ? [ { 'label' => key, 'options' => nil } ] : []
            },
            'messages' => lambda { |state|
              archetype_key = lambda { |name| Outstanding.archetype?(state, name) }

              Outstanding.spell_messages(state, key, archetype_key)
            }
          }
        end.freeze

        # The remaining keys: one open marker each, one message each.
        SIMPLE_KEYS = [
          [ 'signature', 'pf2e.adv_item_signaturespells' ],
          [ 'archetype_specialty', 'pf2e.adv_item_archetype_specialty' ],
          [ 'archetype specialty choice', 'pf2e.adv_item_archetype_specialty_choice' ],
          [ 'archetype key ability', 'pf2e.adv_item_archetype_key_ability' ],
          [ 'archetype deity', 'pf2e.adv_item_archetype_deity' ],
          # Underscored in to_assign as well as in the draft, unlike the deity beside it.
          [ 'archetype_sanctification', 'pf2e.adv_item_archetype_sanctification' ]
        ].freeze

        SIMPLE_SOURCES = SIMPLE_KEYS.map do |(key, locale_key)|
          {
            'kind' => key, 'askable' => false,
            'elements' => lambda { |state|
              Outstanding.simple_pending?(state, key) ? [ { 'label' => key, 'options' => nil } ] : []
            },
            'messages' => lambda { |state|
              Outstanding.simple_pending?(state, key) ? [ [ locale_key, {} ] ] : []
            }
          }
        end.freeze

        # What a feat handed over that has still to be resolved. Named by the feat, because that
        # is what the player recognises.
        GRANT_SOURCE = {
          'kind' => 'grants', 'askable' => true,
          'elements' => lambda { |state|
            (state['to_assign']['grants'] || {}).keys.map { |feat| { 'label' => feat, 'options' => nil } }
          },
          'messages' => lambda { |state|
            (state['to_assign']['grants'] || {}).keys.map { |feat| [ 'pf2e.adv_item_grants', { 'feat' => feat } ] }
          }
        }.freeze

        ALL = (SOURCES + SPELL_SOURCES + SIMPLE_SOURCES + [ GRANT_SOURCE ]).freeze

        # Whether one of the single-marker keys is still open. Each has its own shape: a bare
        # 'open', a list that may contain one, or a hash of entries each carrying a choice.
        def self.simple_pending?(state, key)
          info = state['to_assign'][key]

          case key
          when 'signature' then signature_pending?(info)
          when 'archetype specialty choice'
            info.is_a?(Hash) && info.values.any? { |e| e.is_a?(Hash) && open_marker?(e['choice']) }
          when 'archetype key ability'
            info.is_a?(Array) ? !info.empty? : open_marker?(info)
          else open_marker?(info)
          end
        end

        def self.archetype?(state, name)
          Array(state['config'].read('pf2e_archetype')&.keys).any? { |arch| arch.to_s.casecmp?(name.to_s) }
        end

        def self.elements(state)
          ALL.flat_map { |source| source['elements'].call(state).map { |e| e.merge('kind' => source['kind']) } }
        end

        def self.elements_of(kind, state)
          row = ALL.find { |source| source['kind'] == kind }

          row ? row['elements'].call(state) : []
        end

        # Everything the review screen has to say, as [ locale key, args ] pairs for the shell to
        # render. Ordered by the table rather than by whatever order the draft hash happens to be
        # in, so the same draft reads the same way twice.
        def self.messages(state)
          ALL.flat_map { |source| source['messages'] ? source['messages'].call(state) : [] }
        end

        def self.any?(state)
          !messages(state).empty?
        end

        # What advance/info can describe, which is not everything outstanding: a boost or a
        # language has no list of options to show.
        def self.labels(state)
          askable = ALL.select { |source| source['askable'] }.map { |source| source['kind'] }

          elements(state).select { |e| askable.include?(e['kind']) }.map { |e| e['label'] }.uniq.sort
        end

        # A class feature awaiting a pick, as [ feature, options ], or nil. Used by
        # advance/info to describe one element rather than list them all.
        def self.class_option(state, label)
          found = elements(state).find do |e|
            e['kind'] == 'class_option' && e['label'].to_s.casecmp?(label.to_s)
          end

          found && [ found['label'], found['options'] ]
        end
      end
    end
  end
end
