require "plugin_test_loader"
require_relative "support/roll_audit"

module AresMUSH
  module Pf2e

    # What the played encounters' audit says of a hit that leaves a character at nothing.
    describe RollAudit do

      def stood(overrides = {})
        { 'hp' => 50, 'dying' => 0, 'wounded' => 0, 'doomed' => 0, 'dead' => false }.merge(overrides)
      end

      def left(overrides = {})
        stood('hp' => 0).merge(overrides)
      end

      def found_for(before, after, critical, dealt = nil)
        audit = RollAudit.new
        audit.hit_dropped('Aria', before, after, critical, dealt)
        audit.findings.map { |one| one['kind'] }
      end

      it "should pass a hit that leaves them Dying 1, and a critical hit Dying 2" do
        expect(found_for(stood, left('dying' => 1), false)).to eq []
        expect(found_for(stood, left('dying' => 2), true)).to eq []
      end

      it "should find a critical hit that kills someone who was standing unwounded" do
        expect(found_for(stood, left('dying' => 4, 'dead' => true), true)).to eq [ 'dying' ]
      end

      it "should find a hit that raised Dying by more than it should" do
        expect(found_for(stood, left('dying' => 3), true)).to eq [ 'dying' ]
      end

      it "should pass a death at the value that is death" do
        expect(found_for(stood('wounded' => 2), left('dying' => 4, 'dead' => true), true)).to eq []
        expect(found_for(left('dying' => 2, 'doomed' => 1), left('dying' => 3, 'dead' => true, 'doomed' => 1), false)).to eq []
      end

      it "should pass someone spared at the value that is death" do
        expect(found_for(stood('wounded' => 3), left('wounded' => 4), false)).to eq []
      end

      it "should say nothing of a hit that left them standing" do
        expect(found_for(stood, stood('hp' => 12), true)).to eq []
      end

      it "should say nothing of a hit on someone dying that their resistances took all of" do
        expect(found_for(left('dying' => 1), left('dying' => 1), false, 0)).to eq []
      end

      it "should still find a hit on someone dying that landed and left them as they were" do
        expect(found_for(left('dying' => 1), left('dying' => 1), false, 5)).to eq [ 'dying' ]
      end
    end
  end
end
