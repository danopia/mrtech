# connect to the database
ActiveRecord::Base.establish_connection({
      :adapter => "sqlite3", 
      :dbfile => "db/database.sqlite3"
})

class Factoid < ActiveRecord::Base
  validates_uniqueness_of :key
  
  # This way we can use LIKE for case-insensetivity
  def self.find_by_key(key)
    Factoid.first(:conditions => ['key LIKE ?', key])
  end
end

class Karma < ActiveRecord::Base
  def self.count(target)
    count = 0
    Karma.all(:conditions => ['target LIKE ?', target]).each do |karma|
      count += (karma.positive ? 1 : -1)
    end
    count
  end
  
  # This way we can use LIKE for case-insensetivity
  def find_by_target_and_voter(target, voter)
    Factoid.first(:conditions => ['target LIKE ? AND voter LIKE ?', target, voter])
    #return nil unless records && records.size > 0
    #records[0]
  end
  
  def negative
    !positive
  end
  def negative=(value)
    positive = !value
  end
end

class RedmineIssue < ActiveRecord::Base
end

class RedmineJournal < ActiveRecord::Base
end
