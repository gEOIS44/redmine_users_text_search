module RedmineUsersTextSearch
  module Patches
    module UsersTextSearchIssuesControllerPatch
      def self.included(base)
        base.send(:include, UsersTextSearchInstanceMethods)
        base.class_eval do
          unloadable
          alias_method_chain :index, :user_text_search
        end
      end

      module UsersTextSearchInstanceMethods
        def index_with_user_text_search
          if params.has_key?(:assigned_to_id)
            case params[:assigned_to_id]
            when "me"
              params[:assigned_to] = "#{User.current.name} (#{User.current.id})"
            else
              user = User.find(params[:assigned_to_id])
              params[:assigned_to] = "#{user.name} (#{params[:assigned_to_id]})" if user.present?
            end
          end

          if params.has_key?(:author_id)
            case params[:author_id]
            when "me"
              params[:author] = "#{User.current.name} (#{User.current.id})"
            else
              user = User.find(params[:author_id])
              params[:author] = "#{user.name} (#{params[:author_id]})" if user.present?
            end
          end
          index_without_user_text_search
        end
      end
    end
  end
end

unless IssuesController.included_modules.include?(RedmineUsersTextSearch::Patches::UsersTextSearchIssuesControllerPatch)
  IssuesController.send(:include, RedmineUsersTextSearch::Patches::UsersTextSearchIssuesControllerPatch)
end
