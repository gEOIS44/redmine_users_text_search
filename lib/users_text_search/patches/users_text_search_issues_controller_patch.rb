module RedmineUsersTextSearch
  module IssuesControllerPatch
    def index
      if params.key?(:assigned_to_id)
        case params[:assigned_to_id]
        when "me"
          params[:assigned_to] = "#{User.current.name} (#{User.current.id})"
        else
          user = User.find(params[:assigned_to_id])
          params[:assigned_to] = "#{user.name} (#{user.id})" if user.present?
        end
      end

      if params.key?(:author_id)
        case params[:author_id]
        when "me"
          params[:author] = "#{User.current.name} (#{User.current.id})"
        else
          user = User.find(params[:author_id])
          params[:author] = "#{user.name} (#{params[:author_id]})" if user.present?
        end
      end
      super
    end
  end
end

IssuesController.prepend(RedmineUsersTextSearch::IssuesControllerPatch)
