require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # An operator in front of the term only means something on a numeric search. Read off a name,
    # it turned 'feat/search name=Nimble Dodge' into a search for 'Dodge' with 'Nimble' as an
    # operator nothing uses, so every multi-word name searched for its last word alone.
    describe PF2FeatSearchCmd do

      def parsed(type, value)
        cmd = double(:args => "#{type}=#{value}", :page => 1)
        allow(cmd).to receive(:parse_args).and_return(double(:arg1 => type, :arg2 => value))

        handler = PF2FeatSearchCmd.new(double, cmd, double)
        handler.parse_args
        handler
      end

      it "should keep a two-word name whole" do
        expect(parsed('name', 'Nimble Dodge').term_and_operator).to eq [ 'Nimble Dodge', nil ]
      end

      it "should keep a name of any length whole" do
        expect(parsed('name', 'Blessed One Dedication').term_and_operator).to eq [ 'Blessed One Dedication', nil ]
      end

      it "should read the comparison off a level search" do
        expect(parsed('level', '> 3').term_and_operator).to eq [ '3', '>' ]
      end

      # classlevel is 'this class, at this level', so its first word is the class.
      it "should read the class off a classlevel search" do
        expect(parsed('classlevel', 'Wizard 4').term_and_operator).to eq [ '4', 'Wizard' ]
      end
    end
  end
end
