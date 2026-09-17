module AresMUSH
  module Pf2e
    module Advancement

      # What a level offers, one row per key of a class table's level block.
      #
      # The counterpart of Advancement::Apply: this turns the table into a draft and a pool of open
      # picks, and Apply turns the finished draft into the sheet. Between them they are the whole
      # vocabulary of a level.
      #
      #   pool   - what the player still has to choose, written to pf2_to_assign
      #   draft  - what the level gives outright, written to pf2_advancement
      #
      # A row's `open` takes the context and mutates the two hashes it is handed, returning
      # [ locale key, args ] pairs for the shell. A key with no row goes to the draft as it stands,
      # which is how a key Apply knows and this does not - a tradition raise, an action - reaches
      # the sheet; the two tables are checked against each other by spec.
      module Opens

        KEYS = {
          # Feat slots, one pool keyed by type. The same shape chargen uses.
          'choose_feat' => {
            'open' => lambda { |ctx|
              slots = ctx[:pool]['feats'] || {}

              Array(ctx[:value]).each { |type| slots[type] = [ 'open' ] }

              ctx[:pool]['feats'] = slots

              Array(ctx[:value]).map { |type| [ 'pf2e.adv_item_feat', { :value => type } ] }
            }
          },
          # Both keys name choices a feat or feature carries, and granted_choice_names reads them
          # off the whole level block at once - so a level carrying both does not open each twice.
          'feat_choice' => { 'open' => lambda { |_ctx| [] } },
          'grant_choice' => { 'open' => lambda { |_ctx| [] } },
          # Spellcasting splits in two: the stats the level simply gives, and the picks it opens.
          'magic_stats' => {
            'open' => lambda { |ctx|
              assessed = PF2Magic.assess_magic_stats(ctx[:char], ctx[:value])

              ctx[:draft]['magic_stats'] = assessed['magic_stats']

              options = assessed['magic_options']

              next [] unless options

              options.each_pair { |key, value| ctx[:pool][key] = value }

              Pf2e.magic_option_messages(options.keys)
            }
          },
          # An increase to pick, one slot per thing the level says can be raised. Attributes come
          # four at a time, which is what PF2e gives at 5th, 10th, 15th and 20th.
          'raise' => {
            'open' => lambda { |ctx|
              Array(ctx[:value]).map do |item|
                ctx[:pool]["raise #{item}"] = item == 'ability' ? Array.new(4, 'open') : [ 'open' ]

                [ 'pf2e.adv_item_raise', { :item => item } ]
              end
            }
          },
          'choose' => { 'open' => lambda { |ctx| Opens.class_option(ctx) } },
          'charclass_choice' => { 'open' => lambda { |ctx| Opens.class_option(ctx) } }
        }.freeze

        def self.keys
          KEYS.keys
        end

        # A class feature the player picks an option for. The options are a list, or a hash when
        # each option carries what it grants.
        def self.class_option(ctx)
          name = ctx[:value]['choice_name']
          options = ctx[:value]['options']
          choices = ctx[:pool]['class option'] || {}

          choices[name] = options.is_a?(Hash) ? options : Array(options)
          ctx[:pool]['class option'] = choices

          shown = options.is_a?(Hash) ? options.keys : Array(options)

          [ [ 'pf2e.adv_item_choose', { :name => name, :options => shown.sort.join(", ") } ] ]
        end

        # Turns a level block into [ pool, draft, messages ].
        def self.all(char, info)
          pool = {}
          draft = {}

          messages = (info || {}).flat_map do |key, value|
            row = KEYS[key.to_s]

            # A key this does not open is something the level gives outright, and Apply writes it
            # to the sheet when the level commits.
            next (draft[key] = value) && [] unless row

            Array(row['open'].call(:char => char, :value => value, :pool => pool, :draft => draft))
          end

          [ pool, draft, messages ]
        end
      end
    end
  end
end
