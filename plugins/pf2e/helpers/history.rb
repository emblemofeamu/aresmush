require 'json'

module AresMUSH
  module Pf2e

    # An encounter's history: every change in it, which the GM can take back and put back.
    #
    # A change is recorded as what it moved, before and after: each record of the encounter's it touched -
    # its order, turn, cover and concealment, a character's state in it, a creature, an effect, an item
    # a character carries - as it was and as it is, a record that was not there as nothing. Taking one
    # back is putting the before back, whatever the change touched, and putting it back again is putting
    # the after back, with no die rolled twice. What it did not touch is not held: an encounter's
    # characters carry hundreds of items between them, and a fight makes hundreds of changes.
    #
    # What its characters carry is the encounter's own copy (`Equipment`), so it is recorded and put back
    # like anything else, and nothing outside the encounter can move it.
    #
    # The history is one line: `history_at` is how many of its entries are in effect, and recording a new
    # one drops any past that point, which could only have been redone.
    #
    # An ended encounter's history is frozen.
    module History

      # What an encounter holds of its own that a change can move.
      FIELDS = %w{participants next_init round last_number cover concealment trusted current}.freeze

      # What an encounter owns, each by id: the states and creatures in it, and the effects on them. Asked
      # for rather than held in a constant, because the models load after this file.
      def self.owned
        held = { 'states' => [ Pf2eCombatantState, ->(encounter) { encounter.states.to_a } ],
                 'npcs' => [ Pf2eNpc, ->(encounter) { encounter.npcs.to_a } ],
                 'effects' => [ Pf2eEffect, ->(encounter) { Pf2eEffect.find(:encounter_id => encounter.id).to_a } ] }

        # And what its characters carry in it: their copies of their gear.
        Equipment.kinds.each do |collection, model|
          held["items:#{collection}"] = [ model, ->(encounter) { encounter.states.to_a.flat_map { |one| one.public_send(collection).to_a } } ]
        end

        held
      end

      KEY = :pf2e_recording

      # When a row was made and last saved, which are no part of what a change moved.
      STAMPS = [ :created_at, :updated_at ].freeze

      def self.snapshot(encounter)
        encounter = PF2Encounter[encounter.id]
        held = { 'encounter' => plain(FIELDS.to_h { |field| [ field, encounter.public_send(field) ] }) }

        owned.each do |name, (_model, members)|
          held[name] = members.call(encounter).to_h do |one|
            [ one.id.to_s, plain(one.attributes.except(*STAMPS)) ]
          end
        end

        held
      end

      # What moved between two snapshots: `[ before, after ]`, each holding only the records that differ, a
      # record that was not there as nil, and only the encounter's fields that moved.
      def self.difference(before, after)
        was_held = before['encounter'] || {}
        now_held = after['encounter'] || {}
        fields = (was_held.keys | now_held.keys).reject { |field| was_held[field] == now_held[field] }
        was = { 'diff' => true }
        now = { 'diff' => true }

        unless fields.empty?
          was['encounter'] = was_held.slice(*fields)
          now['encounter'] = now_held.slice(*fields)
        end

        (before.keys | after.keys).each do |name|
          next if name == 'encounter'

          then_held = before[name] || {}
          now_held = after[name] || {}
          moved = (then_held.keys | now_held.keys).reject { |id| then_held[id] == now_held[id] }

          next if moved.empty?

          was[name] = moved.to_h { |id| [ id, then_held[id] ] }
          now[name] = moved.to_h { |id| [ id, now_held[id] ] }
        end

        [ was, now ]
      end

      # The encounter as it was: what was there then is put back as it was, including what the change
      # deleted, and what the change created is gone. An entry recorded whole puts the whole encounter
      # back; one recorded as what moved puts back what moved.
      def self.restore(encounter, held)
        return restore_moved(encounter, held) if held['diff']

        held = without_the_deleted(held)
        encounter = PF2Encounter[encounter.id]
        encounter.update(held['encounter'].transform_keys(&:to_sym))

        owned.each do |name, (model, members)|
          wanted = held[name] || {}

          members.call(encounter).each { |one| one.delete unless wanted.key?(one.id.to_s) }

          # What had nothing in it then has no place in the copy, and is emptied again.
          unset = (model.attributes - STAMPS).to_h { |field| [ field, nil ] }

          wanted.each do |id, attributes|
            attributes = attributes.transform_keys(&:to_sym)
            found = model[id]

            if found
              found.update_attributes(unset.merge(attributes))
              found.save
            else
              model.new(attributes.merge(:id => id)).save
            end
          end
        end
      end

      def self.restore_moved(encounter, held)
        held = without_the_deleted_moved(held)
        PF2Encounter[encounter.id].update(held['encounter'].transform_keys(&:to_sym)) if held['encounter']

        owned.each do |name, (model, _members)|
          unset = (model.attributes - STAMPS).to_h { |field| [ field, nil ] }

          (held[name] || {}).each do |id, attributes|
            found = model[id]

            if attributes.nil?
              found&.delete
            elsif found
              found.update_attributes(unset.merge(attributes.transform_keys(&:to_sym)))
              found.save
            else
              model.new(attributes.transform_keys(&:to_sym).merge(:id => id)).save
            end
          end
        end
      end

      def self.plain(value)
        JSON.parse(JSON.dump(value))
      end

      # A copy with nobody in it who has been deleted since: their place in the order, their state and the
      # effects on it, and what they carried. Taking a change back never brings a deleted character back.
      def self.without_the_deleted(held)
        gone = lambda { |id| id && !Character[id] }
        states = (held['states'] || {}).reject { |_id, one| gone.call(one['character_id']) }
        order = Array(held['encounter']['participants']).reject { |row| row.is_a?(Hash) && gone.call(row['char']) }

        kept = lambda { |one| !one['state_id'] || states.key?(one['state_id'].to_s) }
        owned_by_kept = held.select { |name, _| name == 'effects' || name.start_with?('items:') }
                            .transform_values { |members| members.select { |_id, one| kept.call(one) } }

        held.merge(owned_by_kept).merge('encounter' => held['encounter'].merge('participants' => order), 'states' => states)
      end

      # The same of what a change moved: a state, effect or item of someone deleted is not put back, and
      # neither is their place in the order. What holds an effect or an item may be in the change or not.
      def self.without_the_deleted_moved(held)
        gone = lambda { |id| id && !Character[id] }
        states = held['states'] || {}
        owner_gone = lambda do |state_id|
          return false unless state_id

          state = states.key?(state_id.to_s) ? states[state_id.to_s] : Pf2eCombatantState[state_id]&.attributes&.transform_keys(&:to_s)
          state.nil? || gone.call(state['character_id'])
        end

        kept = held.to_h do |name, members|
          next [ name, members ] unless members.is_a?(Hash) && (name == 'states' || name == 'effects' || name.start_with?('items:'))

          [ name, members.reject { |_id, one| one && (name == 'states' ? gone.call(one['character_id']) : owner_gone.call(one['state_id'])) } ]
        end

        if kept.dig('encounter', 'participants')
          order = Array(kept['encounter']['participants']).reject { |row| row.is_a?(Hash) && gone.call(row['char']) }
          kept = kept.merge('encounter' => kept['encounter'].merge('participants' => order))
        end

        kept
      end

      # ------------------------------------------------------------------------------
      # Recording

      # Runs a change and records it, if it changed anything. A change inside another - `+e/as` running
      # a Strike - is part of the outer one.
      #
      # What it moved is what it saved and deleted: each record of the encounter's is read as it was the
      # first time the change writes it (`Tracked`), and as it is once the change is done. Nothing it did
      # not write is read. With `PF2E_HISTORY_CHECK` set, the whole encounter is read before and after as
      # well, and a change whose writes and whose snapshots disagree raises.
      def self.recording(encounter, said)
        return yield if encounter.nil? || !encounter.is_active || Thread.current[KEY]

        Thread.current[KEY] = { 'encounter' => encounter.id.to_s, 'touched' => {}, 'fields' => nil }
        whole = ENV['PF2E_HISTORY_CHECK'] ? snapshot(encounter) : nil

        begin
          dice = DiceTape.recording { yield }
          held = Thread.current[KEY]
        ensure
          Thread.current[KEY] = nil
        end

        before, after = moved(held)
        checked!(encounter, said, whole, before, after) if whole
        append(encounter, said, before, after, dice) unless before.keys == [ 'diff' ]
      end

      # Every save and delete passes here, and a record of the encounter being recorded is noted as it
      # was before the first of them.
      module Tracked
        def save
          held = Thread.current[History::KEY]

          return super unless held.is_a?(Hash)

          made = id.nil?
          History.touching(self, held) unless made
          saved = super
          History.touching(self, held, :made => true) if made
          saved
        end

        def delete
          held = Thread.current[History::KEY]
          History.touching(self, held) if held.is_a?(Hash)
          super
        end
      end

      def self.touching(record, held, made: false)
        if record.is_a?(PF2Encounter)
          held['fields'] ||= fields_of(record.id) if record.id.to_s == held['encounter']
          return
        end

        name = bucket(record, held)

        return unless name

        place = [ name, record.id.to_s ]

        return if held['touched'].key?(place)

        held['touched'][place] = made ? nil : as_stored(record.class, record.id)
      end

      # Which of the encounter's own a record is, if it is one of them.
      def self.bucket(record, held)
        ours = lambda { |encounter_id| encounter_id.to_s == held['encounter'] }

        case record
        when Pf2eCombatantState then ours.call(record.encounter_id) ? 'states' : nil
        when Pf2eNpc then ours.call(record.encounter_id) ? 'npcs' : nil
        when Pf2eEffect then ours.call(record.encounter_id) ? 'effects' : nil
        else
          kind = Equipment.kinds.find { |_collection, model| record.is_a?(model) }
          state = kind && record.respond_to?(:state_id) && record.state_id ? Pf2eCombatantState[record.state_id] : nil

          state && ours.call(state.encounter_id) ? "items:#{kind.first}" : nil
        end
      end

      def self.as_stored(model, id)
        found = model[id]

        found ? plain(found.attributes.except(*STAMPS)) : nil
      end

      def self.fields_of(id)
        encounter = PF2Encounter[id]

        plain(FIELDS.to_h { |field| [ field, encounter.public_send(field) ] })
      end

      # What the writes moved: `[ before, after ]`, as `difference` answers them.
      def self.moved(held)
        was = { 'encounter' => held['fields'] || {} }
        now = { 'encounter' => held['fields'] ? fields_of(held['encounter']) : {} }
        models = owned.transform_values(&:first)

        held['touched'].each do |(name, id), before|
          (was[name] ||= {})[id] = before
          (now[name] ||= {})[id] = as_stored(models[name], id)
        end

        difference(was, now)
      end

      class Disagreement < StandardError; end

      def self.checked!(encounter, said, whole, before, after)
        expected = difference(whole, snapshot(encounter))

        return if expected == [ before, after ]

        raise Disagreement, "#{said}: the writes moved #{[ before, after ].inspect[0, 2000]}, the snapshots #{expected.inspect[0, 2000]}"
      end

      def self.entries(encounter)
        Pf2eEncounterEntry.find(:encounter_id => encounter.id).to_a.sort_by(&:seq)
      end

      # Each entry holds the whole encounter twice, so a long fight's history runs to megabytes. These
      # read the fields asked for from each entry, in one round trip, and none of what it holds:
      # `[ { 'id' =>, 'seq' =>, ... } ]` in order.
      def self.fields(encounter, *names)
        ids = Pf2eEncounterEntry.find(:encounter_id => encounter.id).ids

        return [] if ids.empty?

        redis = Pf2eEncounterEntry.redis
        ids.each { |id| redis.queue('HMGET', Pf2eEncounterEntry.key[id].to_s, 'seq', *names) }

        ids.zip(redis.commit).map { |id, (seq, *rest)| { 'id' => id, 'seq' => seq.to_i }.merge(names.zip(rest).to_h) }
           .sort_by { |one| one['seq'] }
      end

      # The entry at a place in the history, read alone.
      def self.entry(encounter, seq)
        found = fields(encounter).find { |one| one['seq'] == seq }

        found && Pf2eEncounterEntry[found['id']]
      end

      # Every change, for a list of them: what was said, and who spent a Hero Point in it.
      def self.listed(encounter)
        fields(encounter, 'said', 'hero_spent').map do |one|
          { 'seq' => one['seq'], 'said' => one['said'], 'heroes' => (Ohm::DataTypes::DataType::Hash.call(one['hero_spent']) || {}).keys }
        end
      end

      def self.at(encounter)
        PF2Encounter[encounter.id].history_at.to_i
      end

      # The change in effect now: the last one made and not taken back.
      def self.latest(encounter)
        entry(encounter, at(encounter))
      end

      def self.append(encounter, said, before, after, dice = [])
        applied = at(encounter)

        # Anything past the change in effect could only be redone, and there is any only after an undo.
        if Pf2eEncounterEntry.find(:encounter_id => encounter.id).size > applied
          fields(encounter).select { |one| one['seq'] > applied }.each { |one| Pf2eEncounterEntry[one['id']]&.delete }
        end
        before, after = difference(before, after) unless before['diff']
        Pf2eEncounterEntry.create(:encounter => encounter, :seq => applied + 1, :said => said,
                                  :before => before, :after => after, :dice => dice)
        PF2Encounter[encounter.id].update(:history_at => applied + 1)
      end

      # ------------------------------------------------------------------------------
      # Taking back and putting back

      def self.undo(encounter)
        return Err.new(:frozen, 'pf2e.history_frozen', 'id' => encounter.id) unless encounter.is_active

        entry = entry(encounter, at(encounter))

        return Err.new(:nothing_to_undo, 'pf2e.history_nothing_to_undo') unless entry

        restore(encounter, entry.before)
        PF2Encounter[encounter.id].update(:history_at => entry.seq - 1)

        Ok.new(:state => entry)
      end

      def self.redo(encounter)
        return Err.new(:frozen, 'pf2e.history_frozen', 'id' => encounter.id) unless encounter.is_active

        entry = entry(encounter, at(encounter) + 1)

        return Err.new(:nothing_to_redo, 'pf2e.history_nothing_to_redo') unless entry

        restore(encounter, entry.after)
        PF2Encounter[encounter.id].update(:history_at => entry.seq)

        Ok.new(:state => entry)
      end
    end
  end
end
Ohm::Model.prepend(AresMUSH::Pf2e::History::Tracked)
