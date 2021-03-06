# Fat Free CRM
# Copyright (C) 2008-2010 by Michael Dvorkin
#
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU Affero General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU Affero General Public License for more details.
#
# You should have received a copy of the GNU Affero General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#------------------------------------------------------------------------------

# == Schema Information
# Schema version: 26
#
# Table name: contacts
#
#  id          :integer(4)      not null, primary key
#  user_id     :integer(4)
#  lead_id     :integer(4)
#  assigned_to :integer(4)
#  reports_to  :integer(4)
#  first_name  :string(64)      default(""), not null
#  last_name   :string(64)      default(""), not null
#  access      :string(8)       default("Private")
#  title       :string(64)
#  department  :string(64)
#  source      :string(32)
#  email       :string(64)
#  alt_email   :string(64)
#  phone       :string(32)
#  mobile      :string(32)
#  fax         :string(32)
#  blog        :string(128)
#  linkedin    :string(128)
#  facebook    :string(128)
#  twitter     :string(128)
#  born_on     :date
#  do_not_call :boolean(1)      not null
#  deleted_at  :datetime
#  created_at  :datetime
#  updated_at  :datetime
#  background_info  :string(255)
#
class Contact < ActiveRecord::Base
  belongs_to  :user
  belongs_to  :lead
  belongs_to  :assignee, :class_name => "User", :foreign_key => :assigned_to
  has_one     :account_contact, :dependent => :destroy
  has_one     :account, :through => :account_contact
  has_many    :contact_opportunities, :dependent => :destroy
  has_many    :opportunities, :through => :contact_opportunities, :uniq => true, :order => "opportunities.id DESC"
  has_many    :tasks, :as => :asset, :dependent => :destroy, :order => 'created_at DESC'
  has_many    :activities, :as => :subject, :order => 'created_at DESC'
  has_one     :business_address, :dependent => :destroy, :as => :addressable, :class_name => "Address", :conditions => "address_type='Business'"

  accepts_nested_attributes_for :business_address, :allow_destroy => true

  named_scope :created_by, lambda { |user| { :conditions => [ "user_id = ?", user.id ] } }
  named_scope :assigned_to, lambda { |user| { :conditions => ["assigned_to = ?", user.id ] } }

  simple_column_search :first_name, :last_name, :escape => lambda { |query| query.gsub(/[^\w\s\-\.']/, "").strip }
  uses_user_permissions
  acts_as_commentable
  acts_as_paranoid
  sortable :by => [ "first_name ASC",  "last_name ASC", "created_at DESC", "updated_at DESC" ], :default => "created_at DESC"

  validates_presence_of :first_name, :message => :missing_first_name
  validates_presence_of :last_name, :message => :missing_last_name
  validate :users_for_shared_access

  comma do
    first_name
    last_name
    email
    phone
    title
    department
    alt_email "Alternative email"
    mobile
    business_address :full_address_without_line_breaks => "Address"
    fax
    do_not_call
    blog "Website/Blog"
    linkedin "LinkedIn"
    facebook
    twitter
  end

  # Default values provided through class methods.
  #----------------------------------------------------------------------------
  def self.per_page ; 20                  ; end
  def self.outline  ; "long"              ; end
  def self.first_name_position ; "before" ; end

  #----------------------------------------------------------------------------
  def full_name(format = nil)
    if format.nil? || format == "before"
      "#{self.first_name} #{self.last_name}"
    else
      "#{self.last_name}, #{self.first_name}"
    end
  end
  alias :name :full_name

  # Backend handler for [Create New Contact] form (see contact/create).
  #----------------------------------------------------------------------------
  def save_with_account_and_permissions(params)
    account = Account.create_or_select_for(self, params[:account], params[:users])
    self.account_contact = AccountContact.new(:account => account, :contact => self) unless account.id.blank?
    self.opportunities << Opportunity.find(params[:opportunity]) unless params[:opportunity].blank?
    self.save_with_permissions(params[:users])
  end

  # Backend handler for [Update Contact] form (see contact/update).
  #----------------------------------------------------------------------------
  def update_with_account_and_permissions(params)
    account = Account.create_or_select_for(self, params[:account], params[:users])
    self.account_contact = AccountContact.new(:account => account, :contact => self) unless account.id.blank?
    self.update_with_permissions(params[:contact], params[:users])
  end

  # Class methods.
  #----------------------------------------------------------------------------
  def self.create_for(model, account, opportunity, params)
    attributes = {
      :lead_id     => model.id,
      :user_id     => params[:account][:user_id],
      :assigned_to => params[:account][:assigned_to],
      :access      => params[:access]
    }
    %w(first_name last_name title source email alt_email phone mobile blog linkedin facebook twitter do_not_call background_info).each do |name|
      attributes[name] = model.send(name.intern)
    end

    contact = Contact.new(attributes)
    contact.business_address = Address.new(:street1 => model.business_address.street1, :street2 => model.business_address.street2, :city => model.business_address.city, :state => model.business_address.state, :zipcode => model.business_address.zipcode, :country => model.business_address.country, :full_address => model.business_address.full_address, :address_type => "Business") unless model.business_address.nil?

    # Save the contact only if the account and the opportunity have no errors.
    if account.errors.empty? && opportunity.errors.empty?
      # Note: contact.account = account doesn't seem to work here.
      contact.account_contact = AccountContact.new(:account => account, :contact => contact) unless account.id.blank?
      contact.opportunities << opportunity unless opportunity.id.blank?
      if contact.access != "Lead" || model.nil?
        contact.save_with_permissions(params[:users])
      else
        contact.save_with_model_permissions(model)
      end
    end
    contact
  end

  private
  # Make sure at least one user has been selected if the contact is being shared.
  #----------------------------------------------------------------------------
  def users_for_shared_access
    errors.add(:access, :share_contact) if self[:access] == "Shared" && !self.permissions.any?
  end

end
