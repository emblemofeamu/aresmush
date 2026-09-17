require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The options behind each thing a character in chargen can be asked about.
    #
    # One row per element, each saying what must already be chosen before it can be answered and
    # where its options come from. `cg/info` held this as a `case` whose arms each wrote their own
    # prerequisite check, and the list of valid elements was a separate literal in the error
    # message - two places to keep in step by hand.
    describe ChargenInfo do

      def char(base = {}, faith = {})
        double(:pf2_base_info => base, :pf2_faith => faith, :name => 'Someone')
      end

      describe :elements do
        it "should name every element a player can ask about" do
          expect(ChargenInfo.elements).to include(
            'ancestry', 'heritage', 'background', 'charclass', 'specialize', 'specialize_info',
            'deity', 'alignment'
          )
        end

        # By the row's own name, so a pair that both resolved to nothing would not pass.
        it "should accept an alias" do
          expect(ChargenInfo.find('backgrounds')['name']).to eq 'background'
          expect(ChargenInfo.find('class')['name']).to eq 'charclass'
          expect(ChargenInfo.find('align')['name']).to eq 'alignment'
        end

        it "should not find a word that is not an element" do
          expect(ChargenInfo.find('banana')).to be_nil
        end
      end

      describe "an element with no prerequisite" do
        it "should list its options" do
          allow(Global).to receive(:read_config).with('pf2e_ancestry').and_return('Human' => {}, 'Elf' => {})

          outcome = ChargenInfo.options(char, 'ancestry')

          expect(outcome).to be_ok
          expect(outcome.state['options'].sort).to eq [ 'Elf', 'Human' ]
        end
      end

      describe "an element with a prerequisite" do
        it "should refuse until the prerequisite is chosen" do
          outcome = ChargenInfo.options(char, 'heritage')

          expect(outcome).to be_err
          expect(outcome.code).to eq :cannot_find_cginfo
          expect(outcome.args['prereq']).to eq 'ancestry'
        end

        it "should list its options once the prerequisite is chosen" do
          allow(Global).to receive(:read_config).with('pf2e_ancestry', 'Elf', 'heritages').and_return([ 'Woodland Elf' ])

          outcome = ChargenInfo.options(char('ancestry' => 'Elf'), 'heritage')

          expect(outcome).to be_ok
          expect(outcome.state['options']).to eq [ 'Woodland Elf' ]
        end
      end

      # A class with no specialties is a different answer from a class whose specialty has not
      # been chosen yet: the first is "nothing to pick here", said OOC, and the second is a
      # failure telling the player what to do first.
      describe "an element the character's class does not have" do
        it "should say so as an aside rather than a failure" do
          allow(Global).to receive(:read_config).with('pf2e_specialty', 'Fighter').and_return(nil)

          outcome = ChargenInfo.options(char('charclass' => 'Fighter'), 'specialize')

          expect(outcome).to be_err
          expect(outcome.code).to eq :no_cginfo_available
        end
      end

      # The one element that is a computation rather than a lookup: what is left after the
      # class, the specialty and the deity have each had their say.
      describe "alignment" do
        before(:each) do
          allow(Global).to receive(:read_config).with('pf2e', 'allowed_alignments').and_return(%w(LG NG CG LE NE CE))
        end

        it "should offer everything the game allows when nothing narrows it" do
          expect(ChargenInfo.options(char, 'alignment').state['options']).to eq %w(LG NG CG LE NE CE)
        end

        it "should narrow to what the deity allows" do
          allow(Global).to receive(:read_config).with('pf2e_deities', 'Althea', 'allowed_alignments').and_return(%w(LG NG))

          outcome = ChargenInfo.options(char({}, 'deity' => 'Althea'), 'alignment')

          expect(outcome.state['options']).to eq %w(LG NG)
        end

        it "should narrow to the intersection of every source" do
          allow(Global).to receive(:read_config).with('pf2e_deities', 'Althea', 'allowed_alignments').and_return(%w(LG NG CG))
          allow(Global).to receive(:read_config).with('pf2e_class', 'Champion', 'allowed_alignments').and_return(%w(LG LE))

          subject = char({ 'charclass' => 'Champion' }, 'deity' => 'Althea')

          expect(ChargenInfo.options(subject, 'alignment').state['options']).to eq %w(LG)
        end

        it "should treat a source that allows nothing in particular as allowing everything" do
          allow(Global).to receive(:read_config).with('pf2e_class', 'Fighter', 'allowed_alignments').and_return(nil)

          expect(ChargenInfo.options(char('charclass' => 'Fighter'), 'alignment').state['options']).to eq %w(LG NG CG LE NE CE)
        end
      end

      describe "the title shown above the options" do
        it "should be the element as asked for" do
          allow(Global).to receive(:read_config).with('pf2e_background').and_return('Acolyte' => {})

          expect(ChargenInfo.options(char, 'backgrounds').state['title']).to eq 'backgrounds'
        end
      end
    end
  end
end

module AresMUSH
  module Pf2e

    # Every row's options lambda, run against a character who has made every choice. A row that
    # only ever ran with half the character filled in hid a four-argument Global.read_config -
    # which takes three - so `cg/info alignment` raised at the one moment a player needed it:
    # after picking a class and a specialty, deciding what alignment they were allowed.
    describe "every element's options" do

      def complete_char
        double(:name => 'Someone',
               :pf2_base_info => { 'ancestry' => 'Human', 'heritage' => 'Versatile Heritage',
                                   'background' => 'Acolyte', 'charclass' => 'Cleric',
                                   'specialize' => 'Cloistered Cleric', 'specialize_info' => 'Healing' },
               :pf2_faith => { 'deity' => 'Sarenrae', 'alignment' => 'NG' })
      end

      it "should answer for a character who has chosen everything" do
        raised = ChargenInfo::ELEMENTS.filter_map do |row|
          begin
            ChargenInfo.options(complete_char, row['name'])
            nil
          rescue StandardError => e
            "#{row['name']}: #{e.class} #{e.message}"
          end
        end

        expect(raised).to eq []
      end
    end
  end
end
