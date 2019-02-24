require_dependency 'query'

module RedmineUsersTextSearch
  module QueryInclude
    def self.included(base)
      base.operators['me'] = :label_me unless base.operators.key?('me')
      base.operators['ot'] = :label_others unless base.operators.key?('ot')
      unless base.operators_by_filter_type.key?(:user)
        base.operators_by_filter_type[:user] = base.operators_by_filter_type[:string]
        base.operators_by_filter_type[:user] << 'me'
        base.operators_by_filter_type[:user] << 'ot'
      end
    end
  end

  module QueryPatch
    def available_filters_as_json
      new_json = super
      new_json.each do |_field, options|
        options["original_type"] = options["type"]
        options["type"] = :string if options["type"] == :user
      end
      new_json
    end

    def sql_for_default_users_field(field, operator, value, table_name, column_name)
      user_ids = get_user_ids_for_filter(operator, value)
      case operator
      when "=", "~", "me", "ot" # 等しい/含む/自分/自分以外
        user_ids.present? ? "#{table_name}.#{column_name} IN (#{user_ids.join(',')})" : "1=0"
      when "!", "!~" # 等しくない/含まない
        user_ids.present? ? "(#{table_name}.#{column_name} NOT IN (#{user_ids.join(',')}) OR #{table_name}.#{column_name} IS NULL)" : "1=1"
      when "!*" # 設定なし
        "#{table_name}.#{column_name} IS NULL"
      when "*"  # 設定あり
        "#{table_name}.#{column_name} IS NOT NULL"
      else
        raise "Unknown query operator #{operator}"
      end
    end

    def sql_for_custom_field(field, operator, value, custom_field_id)
      filter = @available_filters[field]
      return nil unless filter

      if filter[:field].format.target_class && filter[:field].format.target_class <= User
        value = get_user_ids_for_filter(operator, value).map(&:to_s)
      end
      super(field, operator, value, custom_field_id)
    end

    def sql_for_field(field, operator, value, db_table, db_field, is_custom_filter=false)
      case operator
      when "me"
        "#{db_table}.#{db_field} = #{User.current.id}"
      when "ot"
        "#{db_table}.#{db_field} <> #{User.current.id}"
      else
        super(field, operator, value, db_table, db_field, is_custom_filter)
      end
    end

    def validate_query_filters
      filters.each_pair do |_filter, value|
        if value[:operator] == "me" || value[:operator] == "ot"
          value[:extend_operator] = value[:operator]
          value[:operator] = "*"
        end
      end

      super

      filters.each_pair do |_filter, value|
        if value[:extend_operator] == "me" || value[:extend_operator] == "ot"
          value[:operator] = value[:extend_operator]
        end
      end
    end

    private

    def get_user_ids_for_filter(operator, value)
      user_ids = []
      case operator
      when "=", "!" # 等しい/等しくない
        if value.first =~ /^(.+)\s+(.+)\s+\((\d+)\)$/
          user_id = Regexp.last_match[3].to_i
          user_ids = [user_id]
          if Setting.issue_group_assignment?
            user_ids |= Principal.find(user_id).group_ids
          end
        elsif value.first =~ /^(.+)\s+(.+)$/
          a = Regexp.last_match[1].to_s
          b = Regexp.last_match[2].to_s
          principal_ids = get_principal_ids
          if Setting.issue_group_assignment?
            user_ids = Principal.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
          else
            user_ids = User.where(id: principal_ids).where("((lastname = ? and firstname = ?)or(lastname = ? and firstname = ?))", a, b, b, a).pluck(:id)
          end
        else
          principal_ids = get_principal_ids
          if Setting.issue_group_assignment?
            user_ids = Principal.where(id: principal_ids).where(lastname: value.first).pluck(:id)
          else
            user_ids = User.where(id: principal_ids).where(lastname: value.first).pluck(:id)
          end
        end
        user_ids = [user_ids, EmailAddress.where("address = ?", value.first).pluck(:user_id)].flatten.uniq
      when "!*" # 設定なし
        user_ids = []
      when "*"  # 設定あり
        user_ids = []
      when "~", "!~" # 含む/含まない
        principal_ids = get_principal_ids
        if Setting.issue_group_assignment?
          user_ids = Principal.where(id: principal_ids).like(value.first).pluck(:id)
        else
          user_ids = User.where(id: principal_ids).like(value.first).pluck(:id)
        end
      when "me" # 自分
        user_ids = [User.current.id]
        if Setting.issue_group_assignment?
          user_ids |= User.current.group_ids
        end
      when "ot" # 自分以外
        principal_ids = get_principal_ids
        user_ids = principal_ids - [User.current.id]
        if Setting.issue_group_assignment?
          user_ids -= User.current.group_ids
        end
      else
        raise "Unknown query operator #{operator}"
      end
      user_ids
    end

    def get_principal_ids
      principal_ids = []
      if project
        principal_ids << project.principals.visible.pluck(:id)
        unless project.leaf?
          subprojects = project.descendants.visible.to_a
          principal_ids << Principal.member_of(subprojects).visible.pluck(:id)
        end
      elsif all_projects.any?
        principal_ids << Principal.member_of(all_projects).visible.pluck(:id)
      end
      principal_ids.flatten!
      principal_ids.uniq!
      principal_ids.sort!
      principal_ids -= GroupBuiltin.pluck(:id)
      principal_ids << User.current.id
      principal_ids.uniq
    end

    def modify_available_filter(old_field, new_field, new_options)
      new_available_filters = ActiveSupport::OrderedHash.new
      @available_filters.each do |field, options|
        if field == old_field
          if use_query_filter?
            new_available_filters[new_field] = QueryFilter.new(new_field, new_options)
          else
            new_available_filters[new_field] = new_options
          end
        else
          new_available_filters[field] = options
        end
      end
      @available_filters = new_available_filters
    end

    def use_query_filter?
      Module.const_defined?("QueryFilter") && Module.const_get("QueryFilter").is_a?(Class)
    end
  end
end

Query.prepend(RedmineUsersTextSearch::QueryPatch)
unless Query.included_modules.include?(RedmineUsersTextSearch::QueryInclude)
  Query.send(:include, RedmineUsersTextSearch::QueryInclude)
end
