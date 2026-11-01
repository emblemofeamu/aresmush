require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An encounter's log is a list of its own: a line is added to the end of it, and the encounter's
    # record, which every command reads, does not carry it.
    describe EncounterLog, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @encounter = PF2Encounter.create(:organizer => 'GM', :round => 1)
      end

      after(:each) { PF2Encounter[@encounter.id]&.delete }

      it "should keep each line in order, with what kind of line it is" do
        PF2Encounter.send_to_encounter(@encounter, 'Round 1', :notice => 'round', :notice_details => { 'round' => 1 })
        PF2Encounter.send_to_encounter(@encounter, 'Aria strikes.', :line => 'action')

        expect(EncounterLog.lines(@encounter).map { |one| one.drop(1) }).to eq [ [ 'Round 1', 'round', { 'round' => 1 } ],
                                                                                 [ 'Aria strikes.', nil, nil, 'action' ] ]
      end

      it "should answer the last lines asked for" do
        5.times { |at| PF2Encounter.send_to_encounter(@encounter, "line #{at}") }

        expect(EncounterLog.lines(@encounter, 2).map { |one| one[1] }).to eq [ 'line 3', 'line 4' ]
      end

      it "should not be in the encounter's record" do
        30.times { |at| PF2Encounter.send_to_encounter(@encounter, "line #{at}") }

        expect(JSON.parse(Ohm.redis.call('HGET', PF2Encounter.key[@encounter.id].to_s, 'messages') || '[]')).to eq []
      end

      # Logging a line saved the whole encounter as the caller held it, so a caller holding it from before
      # a change undid that change.
      it "should leave the encounter as it is, whoever logs a line" do
        held = PF2Encounter[@encounter.id]
        PF2Encounter[@encounter.id].update(:round => 2)

        PF2Encounter.send_to_encounter(held, 'Aria strikes.')

        expect(PF2Encounter[@encounter.id].round).to eq 2
      end

      it "should read a log kept in the record before, ahead of what came after" do
        @encounter.update(:messages => [ [ Time.now, 'old line' ] ])
        PF2Encounter.send_to_encounter(@encounter, 'new line')

        expect(EncounterLog.lines(PF2Encounter[@encounter.id]).map { |one| one[1] }).to eq [ 'old line', 'new line' ]
        expect(EncounterLog.lines(PF2Encounter[@encounter.id], 1).map { |one| one[1] }).to eq [ 'new line' ]
      end

      it "should go with the encounter" do
        PF2Encounter.send_to_encounter(@encounter, 'line')
        key = EncounterLog.key(@encounter)
        PF2Encounter[@encounter.id].delete

        expect(Ohm.redis.call('EXISTS', key).to_i).to eq 0
      end
    end
  end
end
