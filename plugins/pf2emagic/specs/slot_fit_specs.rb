require "plugin_test_loader"

module AresMUSH
  module Pf2emagic

    # Whether a set of prepared spells can be placed in the slots a caster has at one rank.
    #
    # PF2e slots are pools, and some pools only accept certain spells: a Wizard's curriculum slot
    # takes a spell from the school's list and nothing else, a Cleric's divine font slot takes
    # heal or harm. The old check compared counts and then gave up, logging "only the first is
    # enforced" whenever a character had two restricted pools at one rank - so the second pool
    # silently accepted anything.
    #
    # Placing spells in pools is an assignment problem, not a counting one, which is why this is
    # a matching rather than a subtraction.
    describe SlotFit do

      def open(capacity)
        { 'capacity' => capacity, 'eligible' => nil }
      end

      def restricted(capacity, eligible)
        { 'capacity' => capacity, 'eligible' => eligible }
      end

      describe "open slots only" do
        it "should fit spells up to the slot count" do
          expect(SlotFit.fits?([ open(3) ], %w(Bless Heal Shield))).to be true
        end

        it "should not fit more spells than slots" do
          expect(SlotFit.fits?([ open(2) ], %w(Bless Heal Shield))).to be false
        end

        it "should fit nothing at all in no slots" do
          expect(SlotFit.fits?([], [])).to be true
        end

        it "should not fit a spell with no slots" do
          expect(SlotFit.fits?([], [ 'Bless' ])).to be false
        end
      end

      describe "a restricted pool" do
        it "should take a spell on its list" do
          expect(SlotFit.fits?([ restricted(1, [ 'Fireball' ]) ], [ 'Fireball' ])).to be true
        end

        it "should refuse a spell that is not on its list" do
          expect(SlotFit.fits?([ restricted(1, [ 'Fireball' ]) ], [ 'Bless' ])).to be false
        end

        it "should match the list however it was capitalised" do
          expect(SlotFit.fits?([ restricted(1, [ 'fireball' ]) ], [ 'Fireball' ])).to be true
        end

        # The count fits either way; what makes this false is that the only slot the ineligible
        # spell could use is already needed by the eligible one.
        it "should not let an ineligible spell borrow a restricted slot" do
          pools = [ open(1), restricted(1, [ 'Fireball' ]) ]

          expect(SlotFit.fits?(pools, %w(Fireball Bless))).to be true
          expect(SlotFit.fits?(pools, %w(Bless Heal))).to be false
        end
      end

      # The case the old check got wrong. Two restricted pools at one rank, and the assignment
      # only works if each spell goes to the right one - a greedy pass that fills the first pool
      # it can gets this wrong, which is why it is a matching.
      describe "two restricted pools" do
        it "should place each spell in the pool that accepts it" do
          pools = [ restricted(1, %w(Fireball Lightning Bolt)), restricted(1, %w(Heal Harm)) ]

          expect(SlotFit.fits?(pools, %w(Fireball Heal))).to be true
        end

        it "should refuse two spells that both need the same pool" do
          pools = [ restricted(1, %w(Fireball)), restricted(1, %w(Heal Harm)) ]

          expect(SlotFit.fits?(pools, %w(Heal Harm))).to be false
        end

        it "should back out of a placement that blocks a later spell" do
          # Greedy order matters: 'Heal' fits both pools, 'Harm' only the second. Assigning
          # 'Heal' to the second pool first and stopping there reports a false negative.
          pools = [ restricted(1, %w(Heal)), restricted(1, %w(Heal Harm)) ]

          expect(SlotFit.fits?(pools, %w(Heal Harm))).to be true
        end
      end

      describe "a spell prepared twice" do
        it "should need a slot for each copy" do
          expect(SlotFit.fits?([ open(2) ], %w(Bless Bless))).to be true
          expect(SlotFit.fits?([ open(1) ], %w(Bless Bless))).to be false
        end
      end

      describe :from_slots do
        it "should build an open pool and one pool per restriction" do
          pools = SlotFit.from_slots(3, 'Curriculum' => { 'count' => 1, 'eligible' => [ 'Fireball' ] })

          expect(pools).to eq [
            { 'capacity' => 3, 'eligible' => nil },
            { 'capacity' => 1, 'eligible' => [ 'Fireball' ] }
          ]
        end

        it "should leave out an empty open pool" do
          expect(SlotFit.from_slots(0, {})).to eq []
        end
      end
    end
  end
end
