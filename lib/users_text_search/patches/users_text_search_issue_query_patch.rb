require_dependency 'issue_query'

module RedmineUsersTextSearch
  module IssueQueryPatch
    def initialize_available_filters
      super
      @available_filters.each do |field, options|
        if field =='author_id'
          modify_available_filter('author_id', 'author', {type: :user})
        elsif field == 'assigned_to_id'
          modify_available_filter('assigned_to_id', 'assigned_to', {type: :user})
#        elsif field == 'watcher_id'
#          modify_available_filter('watcher_id', 'watcher', {type: :user})
        elsif field =~ /cf_\d+/
          if use_query_filter? && options[:field].type == 'IssueCustomField' && options[:field].field_format == 'user'
            modify_available_filter(field, field, {type: :user, values: nil, field: options[:field], name: options[:name]})
          elsif options[:field][:type] == 'IssueCustomField' && options[:field][:field_format] == 'user'
            modify_available_filter(field, field, {type: :user, values: nil, field: options[:field], name: options[:name]})
          end
        end
      end
    end

    def sql_for_author_field(field, operator, value)
      sql_for_default_users_field(field, operator, value, Issue.table_name, "author_id")
    end

    def sql_for_assigned_to_field(field, operator, value)
      sql_for_default_users_field(field, operator, value, Issue.table_name, "assigned_to_id")
    end

#    def sql_for_watcher_field(field, operator, value)
#      user_ids = get_user_ids_for_filter(operator, value)
#      case operator
#      when "me", "ot" # 自分/自分以外
#        sql_for_watcher_id_field(field, "=", user_ids)
#      else
#        sql_for_watcher_id_field(field, operator, user_ids)
#      end
#    end
  end
end

IssueQuery.prepend(RedmineUsersTextSearch::IssueQueryPatch)
