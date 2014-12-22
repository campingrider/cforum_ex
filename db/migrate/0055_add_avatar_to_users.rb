# -*- coding: utf-8 -*-

class AddAvatarToUsers < ActiveRecord::Migration
  def up
    add_attachment :users, :avatar
  end

  def down
    remove_attachment :users, :avatar
  end
end

# eof
