module Zimbra
  class Account
    class << self
      def all(options = {})
        AccountService.all(options)
      end

      def find_by_id(id)
        AccountService.get_by_id(id)
      end

      def find_by_name(name)
        AccountService.get_by_name(name)
      end

      def create(options)
        account = new(options)
        AccountService.create(account)
      end

      def acl_name
        'account'
      end
    end

    attr_accessor :id, :name, :password, :acls, :cos_id, :delegated_admin
    attr_accessor :mail_quota # in bytes
    attr_accessor :status
    attr_accessor :raw_attributes

    attr_accessor :first_name, :last_name, :password, :phone, :home_phone,
      :mobile, :pager, :fax, :company, :title, :street, :city, :state, :postal_code,
      :country
    attr_accessor :old_password

    # readonly attributes
    attr_accessor :created_at, :last_login_at

    def initialize(options = {})
      self.id = options[:id]
      self.name = options[:name]
      self.password = options[:password]
      self.acls = options[:acls] || []
      self.cos_id = (options[:cos] ? options[:cos].id : options[:cos_id])
      self.delegated_admin = options[:delegated_admin]
      self.mail_quota = options[:mail_quota]
      self.status = options[:status]
      self.created_at = options[:created_at]
      self.last_login_at = options[:last_login_at]
      self.raw_attributes = options[:raw_attributes]

      self.first_name = options[:first_name]
      self.last_name = options[:last_name]
      self.phone = options[:phone]
      self.home_phone = options[:home_phone]
      self.mobile = options[:mobile]
      self.pager = options[:pager]
      self.fax = options[:fax]
      self.company = options[:company]
      self.title = options[:title]
      self.street = options[:street]
      self.city = options[:city]
      self.state = options[:state]
      self.postal_code = options[:postal_code]
      self.country = options[:country]
    end

    def delegated_admin=(val)
      @delegated_admin = Zimbra::Boolean.read(val)
    end
    def delegated_admin?
      @delegated_admin
    end

    def save
      AccountService.modify(self)
    end

    def delete
      AccountService.delete(self)
    end

    def change_password
      AccountService.change_password(self)
    end

    # @return Array<String>|nil
    def get_aliases
      AccountService.get_aliases(self)
    end

    # @param alias_name String, example: 'test@google.com'
    def create_alias(alias_name)
      AccountService.create_alias(self, alias_name)
    end
  end

  class AccountService < HandsoapService
    def all(options = {})
      xml = invoke("n2:GetAllAccountsRequest") do |message|
        if options[:by_domain]
          message.add 'domain', options[:by_domain] do |c|
            c.set_attr 'by', 'name'
          end
        end
      end
      Parser.get_all_response(xml)
    end

    def create(account)
      xml = invoke("n2:CreateAccountRequest") do |message|
        Builder.create(message, account)
      end
      Parser.account_response(xml/"//n2:account")
    end

    def get_by_id(id)
      xml = invoke("n2:GetAccountRequest") do |message|
        Builder.get_by_id(message, id)
      end
      return nil if soap_fault_not_found?
      Parser.account_response(xml/"//n2:account")
    end

    def get_by_name(name)
      xml = invoke("n2:GetAccountRequest") do |message|
        Builder.get_by_name(message, name)
      end
      return nil if soap_fault_not_found?
      Parser.account_response(xml/"//n2:account")
    end

    def modify(account)
      xml = invoke("n2:ModifyAccountRequest") do |message|
        Builder.modify(message, account)
      end
      Parser.account_response(xml/'//n2:account')
    end

    def delete(dist)
      xml = invoke("n2:DeleteAccountRequest") do |message|
        Builder.delete(message, dist.id)
      end
    end

    def change_password(account)
      xml = invoke('n2:SetPasswordRequest') do |message|
        message.add 'id', account.id
        message.add 'newPassword', account.password
      end
    end

    # @return Array<String>|nil
    def get_aliases(account)
      xml = invoke("n2:GetAccountRequest") do |message|
        Builder.get_by_id(message, account.id)
      end
      return nil if soap_fault_not_found?
      Parser.account_response_aliases(xml/"//n2:account")
    end

    # @param account ::Zimbra::Account
    # @param alias_name String, example: 'test@google.com'
    def create_alias(account, alias_name)
      xml = invoke('n2:AddAccountAliasRequest') do |message|
        message.add 'id', account.id
        message.add 'alias', alias_name
      end
    end

    class Builder
      class << self
        def create(message, account)
          message.add 'name', account.name
          message.add 'password', account.password
          A.inject(message, 'zimbraCOSId', account.cos_id)
          A.inject(message, 'zimbraMailQuota', account.mail_quota)
          if account.raw_attributes
            account.raw_attributes.each do |key, val|
              Zimbra::A.inject(message, key, val)
            end
          end
        end

        def get_by_id(message, id)
          message.add 'account', id do |c|
            c.set_attr 'by', 'id'
          end
        end

        def get_by_name(message, name)
          message.add 'account', name do |c|
            c.set_attr 'by', 'name'
          end
        end

        def modify(message, account)
          message.add 'id', account.id
          modify_attributes(message, account)
        end
        def modify_attributes(message, account)
          if account.acls.empty?
            ACL.delete_all(message)
          else
            account.acls.each do |acl|
              acl.apply(message)
            end
          end
          Zimbra::A.inject(message, 'zimbraCOSId', account.cos_id)
          Zimbra::A.inject(message, 'zimbraIsDelegatedAdminAccount', (account.delegated_admin? ? 'TRUE' : 'FALSE'))
          Zimbra::A.inject(message, 'zimbraMailQuota', account.mail_quota)
          if account.status && !account.raw_attributes
            Zimbra::A.inject(message, 'zimbraAccountStatus', account.status)
          end
          if account.raw_attributes
            account.raw_attributes.each do |key, val|
              Zimbra::A.inject(message, key, val)
            end
          end
        end

        def delete(message, id)
          message.add 'id', id
        end
      end
    end
    class Parser
      class << self
        def get_all_response(response)
          (response/"//n2:account").map do |node|
            account_response(node)
          end
        end

        def account_response(node)
          id = (node/'@id').to_s
          name = (node/'@name').to_s
          acls = Zimbra::ACL.read(node)
          cos_id = Zimbra::A.read(node, 'zimbraCOSId')
          delegated_admin = Zimbra::A.read(node, 'zimbraIsDelegatedAdminAccount')
          mail_quota = Zimbra::A.single_read(node, 'zimbraMailQuota').to_i
          status = Zimbra::A.single_read(node, 'zimbraAccountStatus')
          created_at = DateTime.parse(Zimbra::A.single_read(node, 'zimbraCreateTimestamp'))
          last_login_at = Zimbra::A.single_read(node, 'zimbraLastLogonTimestamp')
          if last_login_at && !last_login_at.empty?
            last_login_at = DateTime.parse(last_login_at)
          end
          first_name = Zimbra::A.single_read(node, 'givenName')
          last_name = Zimbra::A.single_read(node, 'sn')
          password = Zimbra::A.single_read(node, 'password')
          phone = Zimbra::A.single_read(node, 'telephoneNumber')
          home_phone = Zimbra::A.single_read(node, 'homePhone')
          mobile = Zimbra::A.single_read(node, 'mobile')
          pager = Zimbra::A.single_read(node, 'pager')
          fax = Zimbra::A.single_read(node, 'facsimileTelephoneNumber')
          company = Zimbra::A.single_read(node, 'company')
          title = Zimbra::A.single_read(node, 'title')
          street = Zimbra::A.single_read(node, 'street')
          city = Zimbra::A.single_read(node, 'l')
          state = Zimbra::A.single_read(node, 'st')
          postal_code = Zimbra::A.single_read(node, 'postalCode')
          country = Zimbra::A.single_read(node, 'co')
          Zimbra::Account.new(
            :id => id,
            :name => name,
            :acls => acls,
            :cos_id => cos_id,
            :delegated_admin => delegated_admin,
            :mail_quota => mail_quota,
            :status => status,
            :created_at => created_at,
            :last_login_at => last_login_at,

            :first_name => first_name,
            :last_name => last_name,
            :password => password,
            :phone => phone,
            :home_phone => home_phone,
            :mobile => mobile,
            :pager => pager,
            :fax => fax,
            :company => company,
            :title => title,
            :street => street,
            :city => city,
            :state => state,
            :postal_code => postal_code,
            :country => country,
          )
        end

        # @return Array<String>
        def account_response_aliases(node)
          res = Zimbra::A.read(node, 'zimbraMailAlias')
          if res
            Array === res ? res : [res]
          else
            []
          end
        end
      end
    end
  end
end
