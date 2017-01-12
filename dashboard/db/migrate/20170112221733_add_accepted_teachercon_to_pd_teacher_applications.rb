class AddAcceptedTeacherconToPdTeacherApplications < ActiveRecord::Migration[5.0]
  def change
    add_column :pd_teacher_applications, :accepted_teachercon, :string
  end
end
