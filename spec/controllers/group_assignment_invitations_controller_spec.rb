# frozen_string_literal: true
require 'rails_helper'

RSpec.describe GroupAssignmentInvitationsController, type: :controller do
  let(:organization) { GitHubFactory.create_owner_classroom_org }
  let(:user)         { GitHubFactory.create_classroom_student   }

  let(:student_identifier_type) { create(:student_identifier_type, organization: organization) }

  describe 'GET #show', :vcr do
    let(:invitation) { create(:group_assignment_invitation) }

    context 'unauthenticated request' do
      it 'redirects the new user to sign in with GitHub' do
        get :show, id: invitation.key
        expect(response).to redirect_to(login_path)
      end
    end

    context 'student identifier required' do
      before(:each) do
        invitation.group_assignment.student_identifier_type = student_identifier_type
        invitation.group_assignment.save
        sign_in(user)
      end

      it 'redirects to the identifier page' do
        get :show, id: invitation.key
        expect(response).to redirect_to(identifier_group_assignment_invitation_path)
      end

      context 'user already has an identifier value' do
        before do
          StudentIdentifier.create(organization: organization,
                                   user: user,
                                   student_identifier_type: student_identifier_type,
                                   value: 'test value')
        end

        it 'will bring user to the page' do
          get :show, id: invitation.key
          expect(response).to have_http_status(:success)
        end
      end
    end
  end

  describe 'PATCH #submit_identifier', :vcr do
    let(:invitation) { create(:group_assignment_invitation) }
    let(:options)    { { value: 'test value' }              }

    before(:each) do
      invitation.group_assignment.student_identifier_type = student_identifier_type
      invitation.group_assignment.save
      sign_in(user)
    end

    after(:each) do
      StudentIdentifier.destroy_all
    end

    it 'creates the students identifier' do
      patch :submit_identifier, id: invitation.key, student_identifier: options
      expect(StudentIdentifier.count).to eql(1)
    end

    it 'has correct identifier value' do
      patch :submit_identifier, id: invitation.key, student_identifier: options
      expect(StudentIdentifier.first.value).to eql('test value')
    end

    it 'redirects to the accepting page' do
      patch :submit_identifier, id: invitation.key, student_identifier: options
      expect(response).to redirect_to(group_assignment_invitation_path)
    end
  end

  describe 'GET #accept', :vcr do
    let(:organization)  { GitHubFactory.create_owner_classroom_org                         }
    let(:grouping)      { Grouping.create(title: 'Grouping 1', organization: organization) }
    let(:group)         { Group.create(title: 'The Group', grouping: grouping)             }
    let(:student)       { GitHubFactory.create_classroom_student                           }

    let(:group_assignment) do
      GroupAssignment.create(creator: organization.users.first,
                             title: 'HTML5',
                             slug: 'html5',
                             grouping: grouping,
                             organization: organization,
                             public_repo: true)
    end

    let(:invitation) { GroupAssignmentInvitation.create(group_assignment: group_assignment) }

    context 'user is already a member of a group in the grouping' do
      render_views

      before do
        sign_in(student)
        group.repo_accesses << RepoAccess.create(user: student, organization: organization)
      end

      it 'returns success status' do
        get :accept, id: invitation.key
        expect(response).to have_http_status(:success)
      end

      after(:each) do
        RepoAccess.destroy_all
        Group.destroy_all
        GroupAssignmentRepo.destroy_all
      end
    end
  end

  describe 'PATCH #accept_invitation', :vcr do
    let(:organization)  { GitHubFactory.create_owner_classroom_org }
    let(:user)          { GitHubFactory.create_classroom_student   }
    let(:grouping)      { Grouping.create(title: 'Grouping 1', organization: organization) }

    let(:group_assignment) do
      GroupAssignment.create(creator: organization.users.first,
                             title: 'HTML5',
                             slug: 'html5',
                             grouping: grouping,
                             organization: organization,
                             public_repo: true)
    end

    let(:invitation) { GroupAssignmentInvitation.create(group_assignment: group_assignment) }

    context 'authenticated request' do
      before(:each) do
        sign_in(user)
        request.env['HTTP_REFERER'] = "http://classroomtest.com/group-assignment-invitations/#{invitation.key}"
      end

      after(:each) do
        RepoAccess.destroy_all
        Group.destroy_all
        GroupAssignmentRepo.destroy_all
      end

      it 'redeems the users invitation' do
        patch :accept_invitation, id: invitation.key, group: { title: 'Code Squad' }

        expect(WebMock).to have_requested(:post, github_url("/organizations/#{organization.github_id}/teams"))
        expect(WebMock).to have_requested(:post, github_url("/organizations/#{organization.github_id}/repos"))

        expect(group_assignment.group_assignment_repos.count).to eql(1)
        expect(user.repo_accesses.count).to eql(1)
      end

      it 'does not allow users to join a group that is not apart of the grouping' do
        other_grouping = Grouping.create(title: 'Other Grouping', organization: organization)
        other_group    = Group.create(title: 'The Group', grouping: other_grouping)

        patch :accept_invitation, id: invitation.key, group: { id: other_group.id }

        expect(group_assignment.group_assignment_repos.count).to eql(0)
        expect(user.repo_accesses.count).to eql(0)
      end

      context 'group has reached maximum number of members' do
        let(:group)   { Group.create(title: 'The Group', grouping: grouping) }
        let(:student) { GitHubFactory.create_classroom_student }

        before(:each) do
          allow_any_instance_of(RepoAccess).to receive(:silently_remove_organization_member).and_return(true)
          group_assignment.update(max_members: 1)
          group.repo_accesses << RepoAccess.create(user: student, organization: organization)
        end

        it 'does not allow user to join' do
          expect_any_instance_of(ApplicationController).to receive(:flash_and_redirect_back_with_message)
          patch :accept_invitation, id: invitation.key, group: { id: group.id }
        end
      end

      context 'group has not reached maximum number of members' do
        let(:group)   { Group.create(title: 'The Group', grouping: grouping) }

        before(:each) do
          group_assignment.update(max_members: 1)
        end

        it 'allows user to join' do
          patch :accept_invitation, id: invitation.key, group: { id: group.id }
        end
      end

      context 'group does not have maximum number of members' do
        let(:group) { Group.create(title: 'The Group', grouping: grouping) }

        it 'allows user to join' do
          patch :accept_invitation, id: invitation.key, group: { id: group.id }
          expect(group_assignment.group_assignment_repos.count).to eql(1)
          expect(user.repo_accesses.count).to eql(1)
        end
      end

      context 'github repository with the same name already exists' do
        before do
          group = Group.create(title: 'The Group', grouping: grouping)
          group_assignment_repo = GroupAssignmentRepo.create!(group_assignment: group_assignment, group: group)
          @original_repository = organization.github_client.repository(group_assignment_repo.github_repo_id)
          group_assignment_repo.delete
          patch :accept_invitation, id: invitation.key, group: { id: group.id }
        end

        it 'creates a new group assignment repo' do
          expect(group_assignment.group_assignment_repos.count).to eql(1)
        end

        it 'new repository name has expected suffix' do
          expect(WebMock).to have_requested(:post, github_url("/organizations/#{organization.github_id}/repos"))
            .with(body: /^.*#{@original_repository.name}-1.*$/)
        end

        after do
          organization.github_client.delete_repository(@original_repository.id)
          GroupAssignmentRepo.destroy_all
          Group.destroy_all
        end
      end
    end
  end

  describe 'GET #successful_invitation' do
    let(:organization)  { GitHubFactory.create_owner_classroom_org }
    let(:user)          { GitHubFactory.create_classroom_student   }
    let(:grouping)      { Grouping.create(title: 'Grouping 1', organization: organization) }
    let(:group)         { Group.create(title: 'The Group', grouping: grouping)             }

    let(:group_assignment) do
      GroupAssignment.create(creator: organization.users.first,
                             title: 'HTML5',
                             slug: 'html5',
                             grouping: grouping,
                             organization: organization,
                             public_repo: true)
    end

    let(:invitation) { GroupAssignmentInvitation.create(group_assignment: group_assignment) }

    before(:each) do
      sign_in(user)
      group.repo_accesses << RepoAccess.create!(user: user, organization: organization)
      @group_assignment_repo = GroupAssignmentRepo.create!(group_assignment: group_assignment, group: group)
    end

    after(:each) do
      RepoAccess.destroy_all
      Group.destroy_all
      GroupAssignmentRepo.destroy_all
    end

    context 'delete github repository after accepting a invitation successfully', :vcr do
      before do
        organization.github_client.delete_repository(@group_assignment_repo.github_repo_id)
        get :successful_invitation, id: invitation.key
      end

      it 'deletes the old group assignment repo' do
        expect { @group_assignment_repo.reload }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'creates a new group assignment repo for the group' do
        expect(GroupAssignmentRepo.last.id).not_to eq(@group_assignment_repo.id)
      end
    end
  end
end
