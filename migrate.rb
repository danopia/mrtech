# require AR
require 'rubygems'
require 'active_record'

# connect to the database (sqlite in this case)
ActiveRecord::Base.establish_connection({
      :adapter => "sqlite3", 
      :dbfile => "db/database.sqlite3"
})


# define the migrations
class CreateFactoids < ActiveRecord::Migration
  def self.up
    create_table :factoids do |t|
      t.string :key
      t.string :value
      t.string :creator
      t.boolean :prefix, :default => true
      t.boolean :action, :default => false
      t.boolean :locked, :default => false
      t.timestamps
    end
  end

  def self.down
    drop_table :factoids
  end
end

class CreateKarma < ActiveRecord::Migration
  def self.up
    create_table :karmas do |t|
      t.string :target
      t.string :voter
      t.boolean :positive, :default => true
      t.timestamps
    end
  end

  def self.down
    drop_table :karmas
  end
end

# run the migrations
#CreateFactoids.migrate(:up)
#CreateKarma.migrate(:up)
