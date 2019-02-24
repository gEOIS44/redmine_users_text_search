require_dependency 'time_entry_query'

module RedmineUsersTextSearch
  module TimeEntryQueryPatch
    def initialize_available_filters
      super
      @available_filters.each do |field, options|
        if field =='user_id'
          modify_available_filter('user_id', 'user', {type: :user})
        elsif field =~ /cf_\d+/ && options[:field][:type] == 'TimeEntryCustomField' && options[:field][:field_format] == 'user'
          options[:type] = :user
          options.delete(:values)
        elsif field =~ /cf_\d+/
          if use_query_filter? && options[:field].type == 'IssueCustomField' && options[:field].field_format == 'user'
            modify_available_filter(field, field, {type: :user, values: nil, field: options[:field], name: options[:name]})
          elsif options[:field][:type] == 'IssueCustomField' && options[:field][:field_format] == 'user'
            modify_available_filter(field, field, {type: :user, values: nil, field: options[:field], name: options[:name]})
          end
        end
      end
    end

    def sql_for_user_field(field, operator, value)
      sql_for_default_users_field(field, operator, value, TimeEntry.table_name, "user_id")
    end
  end
end

TimeEntryQuery.prepend(RedmineUsersTextSearch::TimeEntryQueryPatch)
