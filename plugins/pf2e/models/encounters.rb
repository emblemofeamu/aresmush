module AresMUSH
  class PF2Encounter < Ohm::Model
    include ObjectModel

    attribute :name
    # The initiative order, one row per combatant; `Pf2e::Combatants` reads and writes it.
    attribute :participants, :type => DataType::Array, :default => []
    attribute :next_init, :type => DataType::Integer, :default => 0
    # Its GM: whoever started it, or whoever they handed it to. Held by the character, so a rename keeps
    # it theirs; `organizer` is their name as it was, for an encounter from before owners were held.
    reference :owner, "AresMUSH::Character"
    attribute :organizer
    attribute :is_active, :type => DataType::Boolean, :default => true
    # The running ones, so finding one reads it and none of those that have ended (`running`).
    index :is_active
    attribute :round, :type => DataType::Integer, :default => 0
    attribute :current
    # Its log from before the log was a list of its own (`Pf2e::EncounterLog`), which reads it.
    attribute :messages, :type => DataType::Array, :default => []
    attribute :init_stat

    # `exploration` for an exploration between fights (`Pf2e::Exploration`): no initiative and no turns.
    # Anything else is a fight.
    attribute :mode

    # The last combatant id given. An id is never reused within an encounter, so `#2` means the same
    # creature all fight long.
    attribute :last_number, :type => DataType::Integer, :default => 0

    # Players the GM has trusted with setting cover and concealment, for this encounter only.
    attribute :trusted, :type => DataType::Array, :default => []

    # A target's cover and concealment, by its id: `{ '3' => 'standard' }`.
    attribute :cover, :type => DataType::Hash, :default => {}
    attribute :concealment, :type => DataType::Hash, :default => {}

    # The encounter its characters carry on from, if the GM named one when starting it: whoever was in
    # that one starts this one as they left it. Anyone else starts fresh.
    attribute :carries_on_from

    set :characters, "AresMUSH::Character"
    reference :scene, "AresMUSH::Scene"
    collection :npcs, "AresMUSH::Pf2eNpc", :encounter
    collection :states, "AresMUSH::Pf2eCombatantState", :encounter

    # The party's level for its difficulty, where the GM set one; otherwise the characters' average.
    attribute :party_level, :type => DataType::Integer

    # What staff paid each character for it, by name: `{ 'Aria' => { 'xp' => 80, 'money' => 13500 } }`.
    attribute :awarded, :type => DataType::Hash, :default => {}

    # How many of its history's entries are in effect: undo steps back, redo forward (`Pf2e::History`).
    attribute :history_at, :type => DataType::Integer, :default => 0
    collection :entries, "AresMUSH::Pf2eEncounterEntry", :encounter

    before_delete :delete_combatants

    def delete_combatants
      self.npcs.each(&:delete)
      self.states.each(&:delete)
      self.entries.each(&:delete)
      Pf2e::EncounterLog.delete(self)
    end

    ##### CLASS METHODS #####

    # A character is in an encounter while it has a place for them in its order. `char.encounters` is
    # only where to look: joining adds to it, but nothing that takes them out of the order - `+e/remove`,
    # `+e/undo` - takes them out of it.
    # The running encounters, of those `filters` find: `running(:scene_id => scene.id)`.
    def self.running(filters = {})
      indexed!
      find(filters.merge(:is_active => true))
    end

    # The running encounters a character has been put in, read from the index of running ones.
    def self.running_for(char)
      indexed!
      char.encounters.find(:is_active => true)
    end

    # The index of running encounters is kept as each is saved. One running from before it was kept is
    # saved into it once, the first time it is asked for, and the database remembers that it was.
    INDEXED = 'PF2Encounter:running_indexed'

    def self.indexed!
      return if @indexed

      unless redis.call('EXISTS', INDEXED).to_i.positive?
        all.to_a.select(&:is_active).each(&:save)
        redis.call('SET', INDEXED, Time.now.to_i)
      end

      @indexed = true
    end

    def self.in_active_encounter?(char)
      active_encounters(char).any?
    end

    def self.in_encounter?(char, encounter)
      encounter.is_active && Pf2e::Combatants.rows(encounter).any? { |row| row['char'].to_s == char.id.to_s }
    end

    def self.scene_active_encounter(scene)
      running(:scene_id => scene.id).first
    end

    def self.get_encounter(char, scene=nil)
      return nil unless scene
      scene_active_encounter(scene)
    end

    def self.active_encounters(char)
      running_for(char).select { |e| in_encounter?(char, e) }
    end

    # The encounter's log: `[time, message]`, then for an encounter notice - `start`, `end`, `round` or
    # `turn` - which notice it is and its details, for a page to lay out as its own, and for a line the
    # game told what kind it is - `action` or `system` - for a page to mark it for its reader (see
    # `SystemPrefix`). A line the game told is kept as told, without the prefix.
    def self.send_to_encounter(enc, msg, notice: nil, notice_details: nil, line: nil)
      Pf2e::EncounterLog.add(enc, [ Time.now, msg, notice, notice_details, line ].reverse.drop_while(&:nil?).reverse)
    end

    # Its page on the portal.
    def self.page_url(encounter)
      "#{Game.web_portal_url}/pf2/encounter/#{encounter.id}"
    end

    # Its GM, or staff: admins run every encounter.
    def self.is_organizer?(char, encounter)
      char.is_admin? || owned_by?(char, encounter)
    end

    def self.owned_by?(char, encounter)
      encounter.owner_id ? encounter.owner_id == char.id : char.name == encounter.organizer
    end

    def self.gm_of(encounter)
      encounter.owner || Character.named(encounter.organizer.to_s)
    end

    def self.hand_to(encounter, char)
      encounter.update(:owner => char, :organizer => char.name)
    end

  end
end
