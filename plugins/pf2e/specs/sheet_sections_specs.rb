require "plugin_test_loader"

module AresMUSH
  module Pf2e

    # Which sections of a sheet exist, and whether this character has one.
    #
    # Three commands each carried their own copy of the list and they disagreed: `sheet` did not
    # accept `combat`, which `sheet/show` did, so a player could grant someone a section that
    # `sheet` would then refuse to render - and only `sheet` checked that a character casts
    # before showing them a magic section.
    describe Sheet do

      def caster
        double(:magic => double, :pf2_baseinfo_locked => true, :is_admin? => false, :name => 'Caster')
      end

      def mundane
        double(:magic => nil, :pf2_baseinfo_locked => true, :is_admin? => false, :name => 'Fighter')
      end

      describe :sections do
        it "should include every section a player can be shown" do
          expect(Sheet.sections).to include('all', 'info', 'ability', 'skills', 'feats', 'features', 'languages', 'magic', 'combat')
        end

        it "should recognise a section" do
          expect(Sheet.section?('combat')).to be true
        end

        it "should not recognise a word that is not one" do
          expect(Sheet.section?('banana')).to be false
        end
      end

      describe :available do
        it "should allow a section with nothing to require" do
          expect(Sheet.available(mundane, 'skills')).to be_ok
        end

        it "should refuse a section that is not one" do
          outcome = Sheet.available(mundane, 'banana')

          expect(outcome).to be_err
          expect(outcome.code).to eq :bad_section
        end

        # The check `sheet` had and `sheet/show` did not.
        it "should refuse the magic section to a character who does not cast" do
          outcome = Sheet.available(mundane, 'magic')

          expect(outcome).to be_err
          expect(outcome.code).to eq :not_caster
        end

        it "should allow the magic section to a caster" do
          expect(Sheet.available(caster, 'magic')).to be_ok
        end

        it "should refuse any section on a sheet that does not exist yet" do
          unlocked = double(:magic => nil, :pf2_baseinfo_locked => false, :is_admin? => false, :name => 'New')
          outcome = Sheet.available(unlocked, 'skills')

          expect(outcome).to be_err
          expect(outcome.code).to eq :no_sheet_yet
        end

        it "should refuse an admin's sheet, which does not exist" do
          admin = double(:magic => nil, :pf2_baseinfo_locked => true, :is_admin? => true, :name => 'Staff')
          outcome = Sheet.available(admin, 'skills')

          expect(outcome).to be_err
          expect(outcome.code).to eq :admin_no_sheet
        end

        # Order matters: an admin has no sheet at all, so that is the answer even for a section
        # they would otherwise fail on for a different reason.
        it "should say a sheet does not exist before saying a section is unavailable" do
          admin = double(:magic => nil, :pf2_baseinfo_locked => true, :is_admin? => true, :name => 'Staff')

          expect(Sheet.available(admin, 'magic').code).to eq :admin_no_sheet
        end
      end

      # Whether a *viewer* may see a section, which is a different question from whether the
      # section exists. `sheet/show` let a player grant someone access to a section of their
      # sheet - and nothing ever read the grant: `sheet` and `sheet/combat` consulted only the
      # `open_sheets` config and the staff `view_sheets` permission, so every grant a player made
      # was inert.
      describe :viewable? do
        def viewer(permission: false)
          double(:name => 'Viewer', :has_permission? => permission, :is_admin? => false)
        end

        def shown(grants = {})
          double(:name => 'Subject', :pf2_viewsheet => grants, :is_admin? => false,
                 :has_permission? => false, :pf2_baseinfo_locked => true, :magic => nil)
        end

        before(:each) { allow(Global).to receive(:read_config).with('pf2e', 'open_sheets').and_return(false) }

        it "should let anyone see any sheet when the game says sheets are open" do
          allow(Global).to receive(:read_config).with('pf2e', 'open_sheets').and_return(true)

          expect(Sheet.viewable?(viewer, shown, 'skills')).to be_ok
        end

        it "should let staff with the permission see a sheet" do
          expect(Sheet.viewable?(viewer(:permission => true), shown, 'skills')).to be_ok
        end

        it "should let a character see their own sheet" do
          char = shown

          expect(Sheet.viewable?(char, char, 'skills')).to be_ok
        end

        it "should refuse someone who was never granted anything" do
          outcome = Sheet.viewable?(viewer, shown, 'skills')

          expect(outcome).to be_err
          expect(outcome.code).to eq :cannot_view_sheet
        end

        it "should honour a grant of that section" do
          expect(Sheet.viewable?(viewer, shown('skills' => [ 'Viewer' ]), 'skills')).to be_ok
        end

        it "should honour a grant of the whole sheet" do
          expect(Sheet.viewable?(viewer, shown('all' => [ 'Viewer' ]), 'skills')).to be_ok
        end

        it "should not let a grant of one section open another" do
          expect(Sheet.viewable?(viewer, shown('skills' => [ 'Viewer' ]), 'feats')).to be_err
        end

        it "should match the granted name however it was capitalised" do
          expect(Sheet.viewable?(viewer, shown('skills' => [ 'viewer' ]), 'skills')).to be_ok
        end
      end
    end
  end
end
