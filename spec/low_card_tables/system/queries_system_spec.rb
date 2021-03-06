require 'low_card_tables'
require 'low_card_tables/helpers/database_helper'
require 'low_card_tables/helpers/system_helpers'

describe "LowCardTables query support" do
  include LowCardTables::Helpers::SystemHelpers

  def create_user!(name, deleted, deceased, gender, donation_level)
    out = ::User.new
    out.name = name
    out.deleted = deleted
    out.deceased = deceased
    out.gender = gender
    out.donation_level = donation_level
    out.save!
    out
  end

  before :each do
    @dh = LowCardTables::Helpers::DatabaseHelper.new
    @dh.setup_activerecord!

    create_standard_system_spec_tables!
    create_standard_system_spec_models!

    @user1 = create_user!('User1', false, false, 'female', 10)
    @user2 = create_user!('User2', true, false, 'female', 10)
    @user3 = create_user!('User3', false, true, 'female', 10)
    @user4 = create_user!('User4', false, false, 'male', 10)
    @user5 = create_user!('User5', false, false, 'female', 8)
  end

  after :each do
    drop_standard_system_spec_tables!
  end

  def check_user_ids(users, expected_users)
    users.to_a.map(&:id).sort.should == expected_users.to_a.map(&:id).sort
  end

  it "should allow 'where' clauses that use the association name" do
    check_user_ids(::User.where(:status => { :deleted => false }), [ @user1, @user3, @user4, @user5 ])
  end

  it "should allow 'where' clauses that use the foreign-key name" do
    check_user_ids(::User.where(:user_status_id => ::UserStatus.low_card_ids_matching({ :deleted => false })), [ @user1, @user3, @user4, @user5 ])
  end

  it "should allow 'where' clauses that use delegated properties directly" do
    check_user_ids(::User.where(:deleted => false), [ @user1, @user3, @user4, @user5 ])
  end

  it "should allow 'where' clauses that combine low-card and non-low-card properties" do
    check_user_ids(::User.where(:deleted => false, :name => 'User1'), [ @user1 ])
    check_user_ids(::User.where(:deleted => false, :name => 'User2'), [ ])
  end

  it "should allow 'where' clauses that use an array" do
    check_user_ids(::User.where(:donation_level => [ 8, 10 ]), [ @user1, @user2, @user3, @user4, @user5 ])
  end

  it "should allow 'where' clauses to use a symbol or a string, and work fine either way" do
    check_user_ids(::User.where(:gender => :male), [ @user4 ])
    check_user_ids(::User.where(:gender => 'male'), [ @user4 ])
    check_user_ids(::User.where(:gender => [ :male, :female ]), [ @user1, @user2, @user3, @user4, @user5 ])
    check_user_ids(::User.where(:gender => [ 'male', 'female' ]), [ @user1, @user2, @user3, @user4, @user5 ])
  end

  it "should allow 'where' clauses that use delegated properties with differently-prefixed names directly" do
    define_model_class(:User2, :lctables_spec_users) { has_low_card_table :status, :prefix => :foo, :class => ::UserStatus, :foreign_key => :user_status_id }

    lambda { check_user_ids(::User2.where(:deleted => false), [ ]) }.should raise_error(::ActiveRecord::StatementInvalid)
    check_user_ids(::User2.where(:foo_deleted => false), [ @user1, @user3, @user4, @user5 ])
  end

  it "should not allow 'where' clauses that use non-delegated properties" do
    define_model_class(:User3, :lctables_spec_users) { has_low_card_table :status, :delegate => [ :deceased ], :class => ::UserStatus, :foreign_key => :user_status_id }

    lambda { check_user_ids(::User3.where(:deleted => false), [ ]) }.should raise_error(::ActiveRecord::StatementInvalid)
  end

  it "should compose 'where' clauses correctly" do
    check_user_ids(::User.where(:deleted => false).where(:gender => 'male'), [ @user4 ])
  end

  it "should compose delegated and specified clauses correctly" do
    check_user_ids(::User.where(:deleted => false, :status => { :gender => 'male'}), [ @user4 ])
  end

  it "should allow using low-card properties in the default scope" do
    LowCardTables::VersionSupport.define_default_scope(::User, :deleted => false)
    check_user_ids(::User.all, [ @user1, @user3, @user4, @user5 ])
  end

  it "should allow using low-card properties in arbitrary scopes and the default scope" do
    LowCardTables::VersionSupport.define_default_scope(::User, :deleted => false)
    class ::User < ::ActiveRecord::Base
      scope :foo, lambda { where(:gender => 'female') }
      scope :bar, lambda { where(:status => { :deceased => false }) }
    end

    check_user_ids(::User.all, [ @user1, @user3, @user4, @user5 ])
    check_user_ids(::User.foo, [ @user1, @user3, @user5 ])
    check_user_ids(::User.bar, [ @user1, @user4, @user5 ])
    check_user_ids(::User.foo.bar, [ @user1, @user5 ])
    check_user_ids(::User.bar.foo, [ @user1, @user5 ])
  end

  it "should pick up new low-card rows when using a low-card property in a scope" do
    LowCardTables::VersionSupport.define_default_scope(::User, nil)
    class ::User < ::ActiveRecord::Base
      scope :foo, lambda { where(:deceased => false) }
      scope :bar, lambda { where(:gender => 'female') }
    end

    check_user_ids(::User.all, [ @user1, @user2, @user3, @user4, @user5 ])
    check_user_ids(::User.foo, [ @user1, @user2, @user4, @user5 ])
    check_user_ids(::User.bar, [ @user1, @user2, @user3, @user5 ])

    @user6 = create_user!('User6', false, false, 'female', 7)
    [ @user1, @user2, @user3, @user4, @user5 ].map(&:user_status_id).include?(@user6.user_status_id).should_not be

    check_user_ids(::User.all, [ @user1, @user2, @user3, @user4, @user5, @user6 ])
    check_user_ids(::User.foo, [ @user1, @user2, @user4, @user5, @user6 ])
    check_user_ids(::User.bar, [ @user1, @user2, @user3, @user5, @user6 ])
  end

  it "should blow up if you constrain on low-card foreign keys in a static scope" do
    lambda do
      LowCardTables::VersionSupport.define_default_scope(::User, nil)
      class ::User < ::ActiveRecord::Base
        scope :foo, where(:deleted => false)
      end
    end.should raise_error(LowCardTables::Errors::LowCardStaticScopeError, /user_status_id/mi)

    lambda do
      LowCardTables::VersionSupport.define_default_scope(::User, nil)
      class ::User < ::ActiveRecord::Base
        scope :foo, where(:user_status_id => ::UserStatus.low_card_ids_matching(:deleted => false))
      end
    end.should raise_error(LowCardTables::Errors::LowCardStaticScopeError, /user_status_id/mi)
  end


  it "should not blow up if you constrain on other things in a static scope" do
    LowCardTables::VersionSupport.define_default_scope(::User, nil)
    class ::User < ::ActiveRecord::Base
      scope :foo, where(:name => %w{foo bar})
    end

    ::User.first.should be
  end
end
