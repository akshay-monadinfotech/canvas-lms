require File.expand_path(File.dirname(__FILE__) + '/common')
require File.expand_path(File.dirname(__FILE__) + '/helpers/collaborations_common')
require File.expand_path(File.dirname(__FILE__) + '/helpers/collaborations_specs_common')

describe "collaborations" do
  include_examples "in-process server selenium tests"

  context "a Student's" do
    [['EtherPad', 'etherpad'], ['Google Docs', 'google_docs']].each do |title, type|
      context "#{title} collaboration" do
        before(:each) do
          course_with_student_logged_in
          set_up_google_docs(type)
        end

        if type == 'etherpad' then test_id = 158506 end
        if type == 'google_docs' then test_id = 158504 end
        it 'should be editable', :priority => "1", :test_id => test_id do
          be_editable(type, title)
        end

        if type == 'etherpad' then test_id = 158503 end
        if type == 'google_docs' then test_id = 158505 end
        it 'should be delete-able', :priority => "1", :test_id => test_id do
          be_deletable(type, title)
        end

        if type == 'etherpad' then test_id = 138613 end
        if type == 'google_docs' then test_id = 162356 end
        it 'should display available collaborators', :priority => "1", :test_id => test_id do
          display_available_collaborators(type)
        end

        if type == 'etherpad' then test_id = 162361 end
        if type == 'google_docs' then test_id = 162362 end
        it 'start collaboration with people', :priority => "1", :test_id => test_id do
          select_collaborators_and_look_for_start(type)
        end
      end
    end

    context "Google Docs collaborations with google docs not having access" do
      before(:each) do
        course_with_teacher_logged_in
        set_up_google_docs('google_docs', false)
      end

      it 'should not be editable if google drive does not have access to your account', :priority => "1", :test_id => 162363 do
        no_edit_with_no_access
      end

      it 'should not be delete-able if google drive does not have access to your account', :priority => "2", :test_id => 162365 do
        no_delete_with_no_access
      end
    end
  end

  context "a student's etherpad collaboration" do
    before(:each) do
      course_with_teacher(:active_all => true, :name => 'teacher@example.com')
      student_in_course(:course => @course, :name => 'Don Draper')
    end

    it 'should be visible to the student', :priority => "1", :test_id => 138616 do
      PluginSetting.create!(:name => 'etherpad', :settings => {})

      @collaboration = Collaboration.typed_collaboration_instance('EtherPad')
      @collaboration.context = @course
      @collaboration.attributes = { :title => 'My collaboration',
                                    :user  => @teacher }
      @collaboration.update_members([@student])
      @collaboration.save!

      user_session(@student)
      get "/courses/#{@course.id}/collaborations"

      ff('#collaborations .collaboration').length == 1
    end
  end
end

