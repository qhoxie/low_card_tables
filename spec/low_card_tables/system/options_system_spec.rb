require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe "LowCardTables association options" do
  include LowCardTables::Helpers::SystemHelpers

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
    create_standard_system_spec_models!
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  it "should allow multiple references from a table to the same low-card table, and method delegation should be from the first one added" do
    migrate do
      add_column :lctables_spec_users, :old_user_status_id, :integer
    end

    ::User.reset_column_information
    class ::User < ::ActiveRecord::Base
      has_low_card_table :old_status, :class => ::UserStatus, :foreign_key => :old_user_status_id
    end

    user1 = ::User.new

    user1.name = 'User1'

    user1.deleted = false
    user1.deceased = false
    user1.gender = 'female'
    user1.donation_level = 8

    user1.old_status.deleted = true
    user1.old_status.deceased = false
    user1.old_status.gender = 'male'
    user1.old_status.donation_level = 3

    user1.save!

    user1.user_status_id.should_not == user1.old_user_status_id

    user1_again = ::User.find(user1.id)

    user1_again.user_status_id.should == user1.user_status_id
    user1_again.old_user_status_id.should == user1.old_user_status_id

    user1_again.status.deleted.should == false
    user1_again.status.deceased.should == false
    user1_again.status.gender.should == 'female'
    user1_again.status.donation_level.should == 8

    user1_again.old_status.deleted.should == true
    user1_again.old_status.deceased.should == false
    user1_again.old_status.gender.should == 'male'
    user1_again.old_status.donation_level.should == 3
  end

  it "should not blow away methods that are already there, in the class itself, but still allow calls to super" do
    define_model_class(:UserTest, :lctables_spec_users) do
      def deleted
        [ @_other_deleted, super ]
      end

      def deleted=(x)
        @_other_deleted ||= [ ]
        @_other_deleted << x
        super(x)
      end

      has_low_card_table :status, :class => ::UserStatus
    end

    user1 = ::UserTest.new

    user1.deleted.should == [ nil, nil ]
    user1.deleted = true
    user1.deleted.should == [ [ true ], true ]
    user1.deleted = false
    user1.deleted.should == [ [ true, false ], false ]
  end

  it "should override methods defined in a superclass" do
    class RandomSuperclass < ::ActiveRecord::Base
      self.table_name = :lctables_spec_users

      def deleted
        raise "should never run"
      end

      def deleted=(x)
        raise "should never run"
      end
    end

    class UserTest1 < RandomSuperclass
      has_low_card_table :status, :class => ::UserStatus
    end

    user1 = ::UserTest1.new
    user1.name = 'User1'

    user1.deleted.should == nil
    user1.deleted = true
    user1.deleted.should == true
    user1.deceased = false
    user1.gender = 'female'
    user1.donation_level = 10
    user1.save!

    user1.deleted.should == true
    user1.deleted = false
    user1.deleted.should == false
    user1.save!

    user1.deleted.should == false
  end

  it "should override methods defined in a module, when included before" do
    module RandomModule
      def deleted
        raise "should never run"
      end

      def deleted=(x)
        raise "should never run"
      end
    end

    class UserTest2 < ::ActiveRecord::Base
      include RandomModule

      self.table_name = :lctables_spec_users
      has_low_card_table :status, :class => ::UserStatus
    end

    user1 = ::UserTest2.new
    user1.name = 'User1'

    user1.deleted.should == nil
    user1.deleted = true
    user1.deleted.should == true
    user1.deceased = false
    user1.gender = 'female'
    user1.donation_level = 10
    user1.save!

    user1.deleted.should == true
    user1.deleted = false
    user1.deleted.should == false
    user1.save!

    user1.deleted.should == false
  end

  it "should not override methods defined in a module, when included after" do
    module RandomModule
      def deleted
        "foo#{@_deleted}"
      end

      def deleted=(x)
        @_deleted = x
      end
    end

    class UserTest3 < ::ActiveRecord::Base
      self.table_name = :lctables_spec_users
      has_low_card_table :status, :class => ::UserStatus

      include RandomModule
    end

    user1 = ::UserTest3.new
    user1.name = 'User1'

    user1.deleted.should == 'foo'
    user1.deleted = 'bar'
    user1.deleted.should == 'foobar'
  end

  it "should allow prefixing delegated methods with the association name easily" do
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :prefix => true }

    user1 = ::User.new
    user1.name = 'User1'

    lambda { user1.deleted }.should raise_error(NoMethodError)
    lambda { user1.deceased }.should raise_error(NoMethodError)
    lambda { user1.gender }.should raise_error(NoMethodError)
    lambda { user1.donation_level }.should raise_error(NoMethodError)
    lambda { user1.deleted = true }.should raise_error(NoMethodError)
    lambda { user1.deceased = true }.should raise_error(NoMethodError)
    lambda { user1.gender = 'male' }.should raise_error(NoMethodError)
    lambda { user1.donation_level = 10 }.should raise_error(NoMethodError)

    user1.status_deleted = true
    user1.status_deceased = false
    user1.status_gender = 'female'
    user1.status_donation_level = 10

    user1.save!

    user1.status_deleted.should == true
    user1.status_deceased.should == false
    user1.status_gender.should == 'female'
    user1.status_donation_level.should == 10

    user1.status.deleted.should == true
    user1.status.deceased.should == false
    user1.status.gender.should == 'female'
    user1.status.donation_level.should == 10
  end

  %w{symbol string}.each do |prefix_type|
    it "should allow prefixing delegated methods with any arbitrary #{prefix_type}" do
      prefix = 'foo'
      prefix = prefix.to_sym if prefix_type == 'symbol'
      define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :prefix => prefix }

      user1 = ::User.new
      user1.name = 'User1'

      lambda { user1.deleted }.should raise_error(NoMethodError)
      lambda { user1.deceased }.should raise_error(NoMethodError)
      lambda { user1.gender }.should raise_error(NoMethodError)
      lambda { user1.donation_level }.should raise_error(NoMethodError)
      lambda { user1.deleted = true }.should raise_error(NoMethodError)
      lambda { user1.deceased = true }.should raise_error(NoMethodError)
      lambda { user1.gender = 'male' }.should raise_error(NoMethodError)
      lambda { user1.donation_level = 10 }.should raise_error(NoMethodError)

      user1.foo_deleted = true
      user1.foo_deceased = false
      user1.foo_gender = 'female'
      user1.foo_donation_level = 10

      user1.save!

      user1.foo_deleted.should == true
      user1.foo_deceased.should == false
      user1.foo_gender.should == 'female'
      user1.foo_donation_level.should == 10

      user1.status.deleted.should == true
      user1.status.deceased.should == false
      user1.status.gender.should == 'female'
      user1.status.donation_level.should == 10
    end
  end

  it "should allow defining an association twice, and the second one should win" do
    define_model_class(:User, :lctables_spec_users) do
      has_low_card_table :status
      has_low_card_table :status, :prefix => :foo
    end

    user1 = ::User.new
    user1.name = 'User1'

    lambda { user1.deleted }.should raise_error(NoMethodError)
    lambda { user1.deceased }.should raise_error(NoMethodError)
    lambda { user1.gender }.should raise_error(NoMethodError)
    lambda { user1.donation_level }.should raise_error(NoMethodError)
    lambda { user1.deleted = true }.should raise_error(NoMethodError)
    lambda { user1.deceased = true }.should raise_error(NoMethodError)
    lambda { user1.gender = 'male' }.should raise_error(NoMethodError)
    lambda { user1.donation_level = 10 }.should raise_error(NoMethodError)

    user1.foo_deleted = true
    user1.foo_deceased = false
    user1.foo_gender = 'female'
    user1.foo_donation_level = 10

    user1.save!

    user1.foo_deleted.should == true
    user1.foo_deceased.should == false
    user1.foo_gender.should == 'female'
    user1.foo_donation_level.should == 10

    user1.status.deleted.should == true
    user1.status.deceased.should == false
    user1.status.gender.should == 'female'
    user1.status.donation_level.should == 10
  end

  it "should allow delegating no methods from the has_low_card_table class" do
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :delegate => false }

    user1 = ::User.new
    user1.name = 'User1'

    lambda { user1.deleted }.should raise_error(NoMethodError)
    lambda { user1.deceased }.should raise_error(NoMethodError)
    lambda { user1.gender }.should raise_error(NoMethodError)
    lambda { user1.donation_level }.should raise_error(NoMethodError)
    lambda { user1.deleted = true }.should raise_error(NoMethodError)
    lambda { user1.deceased = true }.should raise_error(NoMethodError)
    lambda { user1.gender = 'male' }.should raise_error(NoMethodError)
    lambda { user1.donation_level = 10 }.should raise_error(NoMethodError)

    user1.status.deleted = true
    user1.status.deceased = false
    user1.status.gender = 'female'
    user1.status.donation_level = 10

    user1.save!

    user1.status.deleted.should == true
    user1.status.deceased.should == false
    user1.status.gender.should == 'female'
    user1.status.donation_level.should == 10
  end

  it "should allow delegating just specified methods from the has_low_card_table class" do
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :delegate => [ 'deleted', :gender ] }

    user1 = ::User.new
    user1.name = 'User1'

    lambda { user1.deceased }.should raise_error(NoMethodError)
    lambda { user1.donation_level }.should raise_error(NoMethodError)
    lambda { user1.deceased = true }.should raise_error(NoMethodError)
    lambda { user1.donation_level = 10 }.should raise_error(NoMethodError)

    user1.deleted = true
    user1.status.deceased = false
    user1.gender = 'female'
    user1.status.donation_level = 10

    user1.save!

    user1.deleted.should == true
    user1.status.deleted.should == true
    user1.status.deceased.should == false
    user1.gender.should == 'female'
    user1.status.gender.should == 'female'
    user1.status.donation_level.should == 10
  end

  it "should allow delegating all methods from the has_low_card_table class except what's excluded" do
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :delegate => { :except => [ 'deceased', :donation_level ] } }

    user1 = ::User.new
    user1.name = 'User1'

    lambda { user1.deceased }.should raise_error(NoMethodError)
    lambda { user1.donation_level }.should raise_error(NoMethodError)
    lambda { user1.deceased = true }.should raise_error(NoMethodError)
    lambda { user1.donation_level = 10 }.should raise_error(NoMethodError)

    user1.deleted = true
    user1.status.deceased = false
    user1.gender = 'female'
    user1.status.donation_level = 10

    user1.save!

    user1.deleted.should == true
    user1.status.deleted.should == true
    user1.status.deceased.should == false
    user1.gender.should == 'female'
    user1.status.gender.should == 'female'
    user1.status.donation_level.should == 10
  end

  it "should blow up if asked to delegate or exclude methods that aren't there" do
    e = nil
    begin
      define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :delegate => [ :foo ] }
    rescue ArgumentError => x
      e = x
    end

    e.message.should match(/foo/mi)
    e.message.should match(/deleted/mi)
    e.message.should match(/deceased/mi)
    e.message.should match(/gender/mi)
    e.message.should match(/donation_level/mi)

    e = nil
    begin
      define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :delegate => { :except => [ :foo ] } }
    rescue ArgumentError => x
      e = x
    end

    e.message.should match(/foo/mi)
    e.message.should match(/deleted/mi)
    e.message.should match(/deceased/mi)
    e.message.should match(/gender/mi)
    e.message.should match(/donation_level/mi)
  end

  it "should combine :prefix and :delegate correctly" do
    define_model_class(:User, :lctables_spec_users) { has_low_card_table :status, :prefix => :foo, :delegate => { :except => [ 'deceased', :donation_level ] } }

    user1 = ::User.new
    user1.name = 'User1'

    lambda { user1.foo_deceased }.should raise_error(NoMethodError)
    lambda { user1.foo_donation_level }.should raise_error(NoMethodError)
    lambda { user1.foo_deceased = true }.should raise_error(NoMethodError)
    lambda { user1.foo_donation_level = 10 }.should raise_error(NoMethodError)

    user1.foo_deleted = true
    user1.status.deceased = false
    user1.foo_gender = 'female'
    user1.status.donation_level = 10

    user1.save!

    user1.foo_deleted.should == true
    user1.status.deleted.should == true
    user1.status.deceased.should == false
    user1.foo_gender.should == 'female'
    user1.status.gender.should == 'female'
    user1.status.donation_level.should == 10
  end

  it "should allow specifying the target class manually"
  it "should allow specifying the foreign key manually"
end
