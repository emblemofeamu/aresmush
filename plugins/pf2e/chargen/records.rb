module AresMUSH
  module Pf2e
    module Chargen

      # The four small things a character owns outright, each a list or a map with a name.
      #
      # A roll shorthand, who they have shown a sheet section to, the notes staff keep on them, and
      # what they are known for. None of them is sheet state, so none is a grant - they are the
      # character's own fields, and `CharState` persists them. What they have in common is the shape
      # of the edit, which is why they are one table rather than four commands doing it by hand.
      #
      #   state   - the key in CharState the record lives under
      #   set     - names a value under a key
      #   unset   - takes a key away
      #   add     - appends to a list
      #
      # A row declares only the operations that make sense for it, so `cnote/remove` on a record with
      # no `unset` is an Err rather than a silent no-op.
      module Records

        RECORDS = {
          'alias' => {
            'state' => 'roll_aliases',
            'set' => 'pf2e.alias_set_ok',
            'unset' => 'pf2e.alias_deleted_ok'
          },
          'cnote' => {
            'state' => 'cnotes',
            'set' => 'pf2e.cnote_added',
            'unset' => 'pf2e.cnote_removed',
            # A note is edited by naming it again, and the player is told which it was.
            'replaced' => 'pf2e.cnote_updated',
            # Removing one names it loosely, so the name has to pick out exactly one note.
            'match' => true
          },
          'viewsheet' => {
            'state' => 'viewsheet',
            'add' => 'pf2e.player_added'
          },
          'known_for' => {
            'state' => 'known_for',
            'add' => 'pf2e.knownfor_set_ok'
          }
        }.freeze

        def self.records
          RECORDS.keys
        end

        def self.row(record)
          RECORDS[record.to_s]
        end

        # Names a value under a key: `alias str=Strength`, `cnote/add Bob/history=...`.
        def self.set(state, args)
          row = row(args['record'])

          return unknown(args['record']) unless row && row['set']

          held = (state[row['state']] || {}).dup
          key = args['key'].to_s
          replaced = held.key?(key)

          held[key] = args['value']

          outcome = Ok.new(:state => state.merge(row['state'] => held))
          outcome = outcome.with_ooc(row['replaced'], 'name' => key) if replaced && row['replaced']

          outcome.with_message(row['set'], 'name' => key, 'alias' => key, 'value' => args['value'],
                                           'char' => state['name'])
        end

        # Takes a key away. A record with `match` resolves a loosely-typed name first, and refuses
        # unless exactly one of its keys answers to it.
        def self.unset(state, args)
          row = row(args['record'])

          return unknown(args['record']) unless row && row['unset']

          held = (state[row['state']] || {}).dup
          asked = args['key'].to_s

          if row['match']
            found = held.keys.select { |key| key.to_s.casecmp?(asked) }

            return Err.new(:not_unique, 'pf2e.not_unique') unless found.size == 1

            asked = found.first
          end

          return Err.new(:not_in_list, 'pf2e.not_in_list', 'option' => asked) unless held.key?(asked)

          held.delete(asked)

          Ok.new(:state => state.merge(row['state'] => held))
            .with_message(row['unset'], 'name' => asked, 'alias' => asked, 'char' => state['name'])
        end

        # Appends to a list, or to a list under a key when the record keeps one list per section.
        def self.add(state, args)
          row = row(args['record'])

          return unknown(args['record']) unless row && row['add']

          held = state[row['state']]
          key = args['key']

          return add_to_list(state, row, Array(held), args) if key.blank?

          under = (held || {}).dup
          list = Array(under[key.to_s])

          if list.any? { |item| item.to_s.casecmp?(args['value'].to_s) }
            return Ok.new(:state => state).with_message(row['add'], 'player' => args['value'],
                                                                   'section' => key, 'char' => state['name'])
          end

          under[key.to_s] = list + [ args['value'] ]

          Ok.new(:state => state.merge(row['state'] => under))
            .with_message(row['add'], 'player' => args['value'], 'section' => key, 'char' => state['name'])
        end

        def self.add_to_list(state, row, list, args)
          Ok.new(:state => state.merge(row['state'] => list + [ args['value'] ]))
            .with_message(row['add'], 'name' => state['name'], 'blurb' => args['value'],
                                      'char' => state['name'])
        end

        def self.unknown(record)
          Err.new(:unknown_record, 'pf2e.bad_option', 'element' => 'record', 'options' => records.join(', '))
        end
      end
    end
  end
end
