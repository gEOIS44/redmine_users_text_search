require_dependency 'time_entry_query'

module RedmineUsersTextSearch
  module Patches
    module UsersTextSearchTimeEntryQueryPatch
      def self.included(base)
        base.send(:include, UsersTextSearchInstanceMethods)
        base.class_eval do
          alias_method_chain :available_filters_as_json, :user_text_search
          alias_method_chain :initialize_available_filters, :user_text_search
          alias_method_chain :sql_for_custom_field, :user_text_search
          alias_method_chain :sql_for_field, :user_text_search
          alias_method_chain :validate_query_filters, :user_text_search
        end

        base.operators['me'] = :label_me unless base.operators.has_key?('me')
        base.operators['ot'] = :label_others unless base.operators.has_key?('ot')
        unless base.operators_by_filter_type.has_key?(:user)
          base.operators_by_filter_type[:user] = base.operators_by_filter_type[:string]
          base.operators_by_filter_type[:user] << 'me'
          base.operators_by_filter_type[:user] << 'ot'
        end
      end

      module UsersTextSearchInstanceMethods
        def available_filters_as_json_with_user_text_search
          new_json = available_filters_as_json_without_user_text_search
          new_json.each do |field, options|
            options["type"] = :string if options["type"] == :user
          end
          new_json
        end

        def initialize_available_filters_with_user_text_search
          initialize_available_filters_without_user_text_search
          @available_filters.each do |field, options|
            if field =='user_id'
              modify_available_filter('user_id', 'user', {type: :user})
            elsif field =~ /cf_\d+/ && options[:field][:type] == 'TimeEntryCustomField' && options[:field][:field_format] == 'user'
              options[:type] = :user
              options.delete(:values)
            elsif field =~ /issue.cf_\d+/ && options[:field][:type] == 'IssueCustomField' && options[:field][:field_format] == 'user'
              options[:type] = :user
              options.delete(:values)
            end
          end
        end

        def sql_for_user_field(field, operator, value)
          user_ids = []
          sql = ''
          case operator
          when "=" # 等しい
            if value.first =~ /^(.+)\s+(.+)\s+\((\d+)\)$/
              a, b, principal_ids = "#{$1}", "#{$2}", ["#{$3}".to_i]
              if Setting.issue_group_assignment?
                user_ids = Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              else
                user_ids = User.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              end
            elsif value.first =~ /^(.+)\s+(.+)$/
              a, b = "#{$1}", "#{$2}"
              principal_ids = get_principal_ids
              if Setting.issue_group_assignment?
                user_ids = Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              else
                user_ids = User.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              end
            end
            sql = user_ids.present? ? "#{TimeEntry.table_name}.user_id IN (#{user_ids.join(',')})" : "1=0"
          when "!" # 等しくない
            if value.first =~ /^(.+)\s+(.+)\s+\((\d+)\)$/
              a, b, principal_ids = "#{$1}", "#{$2}", ["#{$3}".to_i]
              if Setting.issue_group_assignment?
                user_ids = principal_ids - Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              else
                user_ids = User.where(id: principal_ids).pluck(:id)
                user_ids = user_ids - User.where(id: user_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              end
            elsif value.first =~ /^(.+)\s+(.+)$/
              a, b = "#{$1}", "#{$2}"
              principal_ids = get_principal_ids
              if Setting.issue_group_assignment?
                user_ids = principal_ids - Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              else
                user_ids = User.where(id: principal_ids).pluck(:id)
                user_ids = user_ids - User.where(id: user_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
              end
            end
            sql = user_ids.present? ? "#{TimeEntry.table_name}.user_id IN (#{user_ids.join(',')})" : "1=1"
          when "!*" # 設定なし
            sql = "#{TimeEntry.table_name}.user_id IS NULL"
          when "*"  # 設定あり
            sql = "#{TimeEntry.table_name}.user_id IS NOT NULL"
          when "~"  # 含む
            principal_ids = get_principal_ids
            if Setting.issue_group_assignment?
              user_ids = Principal.where(id: principal_ids).like(value.first).pluck(:id)
            else
              user_ids = User.where(id: principal_ids).like(value.first).pluck(:id)
            end
            sql = user_ids.present? ? "#{TimeEntry.table_name}.user_id IN (#{user_ids.join(',')})" : "1=0"
          when "!~" # 含まない
            principal_ids = get_principal_ids
            if Setting.issue_group_assignment?
              user_ids = principal_ids - Principal.where(id: principal_ids).like(value.first).pluck(:id)
            else
              user_ids = User.where(id: principal_ids).pluck(:id)
              user_ids = user_ids - User.where(id: user_ids).like(value.first).pluck(:id)
            end
            sql = user_ids.present? ? "#{TimeEntry.table_name}.user_id IN (#{user_ids.join(',')})" : "1=0"
          when "me" # 自分
            sql = "#{TimeEntry.table_name}.user_id = #{User.current.id}"
          when "ot" # 自分以外
            sql = "#{TimeEntry.table_name}.user_id <> #{User.current.id}"
          else
            raise "Unknown query operator #{operator}"
          end
          sql
        end

        def sql_for_custom_field_with_user_text_search(field, operator, value, custom_field_id)
p "301:sql_for_custom_field_with_user_text_search(field[#{field}], operator[#{operator}], value[#{value}], custom_field_id[#{custom_field_id}])"
          filter = @available_filters[field]
          return nil unless filter
          if filter[:field].format.target_class && filter[:field].format.target_class <= User
            cf_user_ids = []
            case operator
            when "=" # 等しい
              if value.first =~ /^(.+)\s+(.+)\s+\((\d+)\)$/
                a, b, principal_ids = "#{$1}", "#{$2}", ["#{$3}".to_i]
                if Setting.issue_group_assignment?
                  cf_user_ids = Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                else
                  cf_user_ids = User.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                end
              elsif value.first =~ /^(.+)\s+(.+)$/
                a, b = "#{$1}", "#{$2}"
                principal_ids = get_principal_ids
                if Setting.issue_group_assignment?
                  cf_user_ids = Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                else
                  cf_user_ids = User.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                end
              else
                principal_ids = get_principal_ids
                if Setting.issue_group_assignment?
                  cf_user_ids = Principal.where(id: principal_ids).where(login: value.first).pluck(:id)
                else
                  cf_user_ids = User.where(id: principal_ids).where(login: value.first).pluck(:id)
                end
              end
              cf_user_ids = [cf_user_ids, EmailAddress.where("address = ?", value.first).pluck(:user_id)].flatten.uniq
              cf_operator = '='
            when "!" # 等しくない
              if value.first =~ /^(.+)\s+(.+)\s+\((\d+)\)$/
                a, b, principal_ids = "#{$1}", "#{$2}", ["#{$3}".to_i]
                if Setting.issue_group_assignment?
                  cf_user_ids = principal_ids -
                                Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                else
                  user_ids = User.where(id: principal_ids).pluck(:id)
                  cf_user_ids = user_ids -
                                User.where(id: user_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                end
              elsif value.first =~ /^(.+)\s+(.+)$/
                a, b = "#{$1}", "#{$2}"
                principal_ids = get_principal_ids
                if Setting.issue_group_assignment?
                  cf_user_ids = principal_ids -
                                Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                else
                  user_ids = User.where(id: principal_ids).pluck(:id)
                  cf_user_ids = user_ids -
                                User.where(id: user_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
                end
              else
                principal_ids = get_principal_ids
                if Setting.issue_group_assignment?
                  cf_user_ids = principal_ids -
                                Principal.where(id: principal_ids).where(login: value.first).pluck(:id)
                else
                  user_ids = User.where(id: principal_ids).pluck(:id)
                  cf_user_ids = user_ids -
                                User.where(id: user_ids).where(login: value.first).pluck(:id)
                end
              end
              cf_user_ids = cf_user_ids - EmailAddress.where(address: value.first).pluck(:user_id)
              cf_operator = '='
            when "!*" # 設定なし
              cf_operator = operator
            when "*"  # 設定あり
              cf_operator = operator
            when "~"  # 含む
              principal_ids = get_principal_ids
              if Setting.issue_group_assignment?
                cf_user_ids = Principal.where(id: principal_ids).like(value.first).pluck(:id)
              else
                cf_user_ids = User.where(id: principal_ids).like(value.first).pluck(:id)
              end
              cf_operator = '='
            when "!~" # 含まない
              principal_ids = get_principal_ids
              if Setting.issue_group_assignment?
                cf_user_ids = principal_ids - Principal.where(id: principal_ids).like(value.first).pluck(:id)
              else
                user_ids = User.where(id: principal_ids).pluck(:id)
                cf_user_ids = user_ids - User.where(id: user_ids).like(value.first).pluck(:id)
              end
              cf_operator = '='
            when "me" # 自分
              cf_user_ids = [User.current.id]
              cf_operator = operator
            when "ot" # 自分以外
              principal_ids = get_principal_ids
              cf_user_ids = principal_ids - [User.current.id]
              cf_operator = operator
            else
              raise "Unknown query operator #{operator}"
            end
            sql_for_custom_field_without_user_text_search(field, cf_operator, cf_user_ids.map(&:to_s), custom_field_id)
          else
            sql_for_custom_field_without_user_text_search(field, operator, value, custom_field_id)
          end
        end

        def sql_for_field_with_user_text_search(field, operator, value, db_table, db_field, is_custom_filter=false)
          case operator
          when "me"
            sql = "#{db_table}.#{db_field} = #{User.current.id}"
          when "ot"
            sql = "#{db_table}.#{db_field} <> #{User.current.id}"
          else
            sql = sql_for_field_without_user_text_search(field, operator, value, db_table, db_field, is_custom_filter)
          end
          return sql
        end

        def validate_query_filters_with_user_text_search
          filters.each_pair do |filter, value|
            if value[:operator] == "me" || value[:operator] == "ot"
              value[:extend_operator] = value[:operator]
              value[:operator] = "*"
            end
          end

          validate_query_filters_without_user_text_search

          filters.each_pair do |filter, value|
            if value[:extend_operator] == "me" || value[:extend_operator] == "ot"
              value[:operator] = value[:extend_operator]
            end
          end
        end

        private

        def modify_available_filter(old_field, new_field, new_options)
          new_available_filters = ActiveSupport::OrderedHash.new
          @available_filters.each do |field, options|
            if field == old_field
              new_available_filters[new_field] = new_options
            else
              new_available_filters[field] = options
            end
          end
          @available_filters = new_available_filters
        end

        def get_principal_ids
          principal_ids = []
          if project
            principal_ids << project.principals.visible.pluck(:id)
            unless project.leaf?
              subprojects = project.descendants.visible.to_a
              principal_ids << Principal.member_of(subprojects).visible.pluck(:id)
            end
          else
            if all_projects.any?
              principal_ids << Principal.member_of(all_projects).visible.pluck(:id)
            end
          end
          principal_ids.flatten!
          principal_ids.uniq!
          principal_ids.sort!
          principal_ids -= GroupBuiltin.pluck(:id)
          principal_ids << User.current.id
          principal_ids.uniq
        end
      end
    end
  end
end

unless TimeEntryQuery.included_modules.include?(RedmineUsersTextSearch::Patches::UsersTextSearchTimeEntryQueryPatch)
  TimeEntryQuery.send(:include, RedmineUsersTextSearch::Patches::UsersTextSearchTimeEntryQueryPatch)
end