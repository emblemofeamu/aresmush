require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # The XP and money audit. Tagged :dbtest because what it asserts is where the data lives: one
    # row per transaction in its own model, indexed by a sorted set, with the running total on the
    # character.
    describe Audit, :dbtest => true do

      before(:each) do
        bootstrapper = AresMUSH::Bootstrapper.new
        bootstrapper.config_reader.load_game_config
        bootstrapper.db.load_config

        @char = Character.create(:name => "Audit#{rand(1000000)}")
        @char.update(:pf2_xp => 0, :pf2_money => 0)
      end

      after(:each) do
        Audit.delete_all!(@char) if @char
        @char.delete if @char
      end

      describe :post do
        it "should move the running total on the character" do
          Audit.post(@char, 'xp', 500, :by => 'Vardama', :reason => 'Weekly award')

          expect(Character[@char.id].pf2_xp).to eq 500
        end

        it "should record one entry per transaction" do
          Audit.post(@char, 'xp', 500, :by => 'Vardama', :reason => 'Weekly award')
          Audit.post(@char, 'xp', 250, :by => 'Vardama', :reason => 'Scene award')

          expect(Audit.count(@char, 'xp')).to eq 2
          expect(Character[@char.id].pf2_xp).to eq 750
        end

        it "should record what each line was for" do
          Audit.post(@char, 'xp', 500, :by => 'Vardama', :reason => 'Weekly award', :ref => 'job-12')
          entry = Audit.page(@char, 'xp', 1, 10).first

          expect(entry.amount).to eq 500
          expect(entry.by).to eq 'Vardama'
          expect(entry.reason).to eq 'Weekly award'
          expect(entry.ref).to eq 'job-12'
          expect(entry.currency).to eq 'xp'
        end

        # Every line carries the total it produced, so one line explains itself in a dispute
        # without replaying anything before it.
        it "should stamp each entry with the balance it produced" do
          Audit.post(@char, 'xp', 500, :by => 'Staff', :reason => 'first')
          Audit.post(@char, 'xp', -200, :by => 'Staff', :reason => 'second')

          newest, older = Audit.page(@char, 'xp', 1, 10)

          expect(newest.balance_after).to eq 300
          expect(older.balance_after).to eq 500
        end

        it "should take a spend as a negative amount" do
          Audit.post(@char, 'xp', 1000, :by => 'Staff', :reason => 'award')
          Audit.post(@char, 'xp', -1000, :by => 'System', :reason => 'advance to level 2')

          expect(Character[@char.id].pf2_xp).to eq 0
          expect(Audit.count(@char, 'xp')).to eq 2
        end

        it "should keep xp and money apart" do
          Audit.post(@char, 'xp', 500, :by => 'Staff', :reason => 'award')
          Audit.post(@char, 'money', 75, :by => 'Item Vendor', :reason => 'Item Sale')

          expect(Character[@char.id].pf2_xp).to eq 500
          expect(Character[@char.id].pf2_money).to eq 75
          expect(Audit.count(@char, 'xp')).to eq 1
          expect(Audit.count(@char, 'money')).to eq 1
        end

        it "should refuse a currency it does not know" do
          expect { Audit.post(@char, 'favours', 5, :by => 'Staff', :reason => 'x') }.to raise_error(ArgumentError)
        end

        it "should ignore a zero amount rather than writing an empty line" do
          Audit.post(@char, 'xp', 0, :by => 'Staff', :reason => 'nothing')

          expect(Audit.count(@char, 'xp')).to eq 0
        end
      end

      describe :page do
        before(:each) do
          25.times { |i| Audit.post(@char, 'xp', 10, :by => 'Staff', :reason => "award #{i + 1}") }
        end

        it "should return the newest entries first" do
          page = Audit.page(@char, 'xp', 1, 10)

          expect(page.size).to eq 10
          expect(page.first.reason).to eq 'award 25'
          expect(page.last.reason).to eq 'award 16'
        end

        it "should walk back through the pages in order" do
          expect(Audit.page(@char, 'xp', 2, 10).first.reason).to eq 'award 15'
          expect(Audit.page(@char, 'xp', 3, 10).first.reason).to eq 'award 5'
        end

        it "should return a short last page rather than padding it" do
          expect(Audit.page(@char, 'xp', 3, 10).size).to eq 5
        end

        it "should return nothing past the end" do
          expect(Audit.page(@char, 'xp', 9, 10)).to eq []
        end

        it "should count without loading anything" do
          expect(Audit.count(@char, 'xp')).to eq 25
        end

        it "should report how many pages there are" do
          expect(Audit.total_pages(@char, 'xp', 10)).to eq 3
        end

        it "should report one page when there is nothing at all" do
          expect(Audit.total_pages(@char, 'money', 10)).to eq 1
        end
      end

      # Because every entry carries its amount, the total is checkable - which the three
      # records that had to agree by hand never were.
      describe :consistent? do
        it "should agree with the total it produced" do
          Audit.post(@char, 'xp', 500, :by => 'Staff', :reason => 'award')
          Audit.post(@char, 'xp', -120, :by => 'Staff', :reason => 'spend')

          expect(Audit.consistent?(@char, 'xp')).to be true
        end

        it "should notice a total edited behind its back" do
          Audit.post(@char, 'xp', 500, :by => 'Staff', :reason => 'award')
          @char.update(:pf2_xp => 99999)

          expect(Audit.consistent?(Character[@char.id], 'xp')).to be false
        end

        it "should be able to repair the total from the entries" do
          Audit.post(@char, 'xp', 500, :by => 'Staff', :reason => 'award')
          @char.update(:pf2_xp => 99999)

          Audit.repair!(Character[@char.id], 'xp')

          expect(Character[@char.id].pf2_xp).to eq 500
        end
      end

      describe :delete_all! do
        it "should take the entries and the index with it" do
          Audit.post(@char, 'xp', 500, :by => 'Staff', :reason => 'award')
          Audit.post(@char, 'money', 50, :by => 'Staff', :reason => 'purse')

          Audit.delete_all!(@char)

          expect(Audit.count(@char, 'xp')).to eq 0
          expect(Audit.count(@char, 'money')).to eq 0
        end
      end
    end
  end
end
