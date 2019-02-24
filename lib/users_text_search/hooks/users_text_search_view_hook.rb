module RedmineUsersTextSearch
  class UsersTextSearchViewHook < Redmine::Hook::ViewListener
    def view_layouts_base_content(context={})
      javascript_include_tag 'filter_control', plugin: 'redmine_users_text_search'
    end
  end
end
