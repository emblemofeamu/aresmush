module AresMUSH
  module Pf2e
    module Advancement

      # What a character still has to pick before this level-up can be finished.
      #
      # One pure query over the draft, so `advance/info`, the review template and any
      # completeness check all answer the question the same way. Each source is a row in
      # SOURCES: where to look, and how to turn what is there into labels a player can type.
      module Outstanding

        OPEN = 'open'.freeze

        SOURCES = [
          # Class feature choices: a resolved one is stored as the chosen string.
          {
            'kind' => 'class_option',
            'elements' => lambda { |state|
              slot = Options::SLOTS.find { |key| state['to_assign'][key].is_a?(Hash) }

              next [] unless slot

              state['to_assign'][slot].reject { |_feature, options| options.is_a?(String) }
                .map { |feature, options| { 'label' => feature, 'options' => Options.option_list(options).sort } }
            }
          },
          # Choices opened by a feat, which keep their key once resolved - so an entry counts
          # only while one of its slots is still open.
          {
            'kind' => 'feat_choice',
            'elements' => lambda { |state|
              (state['to_assign']['feat choice'] || {})
                .select { |_name, slots| Array(slots).any? { |s| s.to_s.casecmp?(OPEN) } }
                .map { |name, _slots| { 'label' => name, 'options' => nil } }
            }
          },
          # Feat slots the level handed out, by type.
          {
            'kind' => 'feat',
            'elements' => lambda { |state|
              feats = state['to_assign']['feats']

              next [] unless feats.is_a?(Hash)

              feats.select { |_type, slots| Array(slots).any? { |s| s.to_s.casecmp?(OPEN) } }
                .map { |type, _slots| { 'label' => "#{type} feat", 'options' => nil } }
            }
          }
        ].freeze

        def self.elements(state)
          SOURCES.flat_map { |source| source['elements'].call(state).map { |e| e.merge('kind' => source['kind']) } }
        end

        def self.labels(state)
          elements(state).map { |e| e['label'] }.uniq.sort
        end

        def self.any?(state)
          !elements(state).empty?
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
