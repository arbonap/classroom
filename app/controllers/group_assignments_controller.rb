class GroupAssignmentsController < ApplicationController
  before_action :redirect_to_root, unless: :logged_in?

  before_action :set_organization
  before_action :ensure_organization_admin

  before_action :set_group_assignment, except: [:new, :create]
  before_action :set_groupings,        except: [:show]

  rescue_from GitHub::Error,     with: :error
  rescue_from GitHub::Forbidden, with: :deny_access

  def new
    @group_assignment = GroupAssignment.new
  end

  def create
    @group_assignment = GroupAssignment.new(new_group_assignment_params)

    if @group_assignment.save
      CreateGroupingJob.perform_later(@group_assignment, new_grouping_params)
      CreateGroupAssignmentInvitationJob.perform_later(@group_assignment)

      flash[:success] = "\"#{@group_assignment.title}\" has been created!"
      redirect_to organization_group_assignment_path(@organization, @group_assignment)
    else
      render :new
    end
  end

  def show
  end

  private

  def deny_access
    flash[:error] = 'You are not authorized to perform this action'
    redirect_to_root
  end

  def error
    flash[:error] = exception.message
  end

  def ensure_organization_admin
    github_organization = GitHubOrganization.new(current_user.github_client, @organization.github_id)

    login = github_organization.login
    github_organization.authorization_on_github_organization?(login)
  end

  def new_group_assignment_params
    params
      .require(:group_assignment)
      .permit(:title, :public_repo, :grouping_id)
      .merge(organization_id: params[:organization_id])
  end

  def new_grouping_params
    params
      .require(:grouping)
      .permit(:title)
      .merge(organization_id: new_group_assignment_params[:organization_id])
  end

  def set_groupings
    @groupings = @organization.groupings.map { |group| [group.title, group.id] }
  end

  def set_group_assignment
    @group_assignment = GroupAssignment.find(params[:id])
  end

  def set_organization
    @organization = Organization.find(params[:organization_id])
  end
end