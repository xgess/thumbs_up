module ThumbsUp
  module ActsAsVoteable #:nodoc:

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def acts_as_voteable
        has_many :votes, :as => :voteable, :dependent => :destroy

        include ThumbsUp::ActsAsVoteable::InstanceMethods
        extend  ThumbsUp::ActsAsVoteable::SingletonMethods
      end
    end

    module SingletonMethods
      
      # Calculate the plusminus for a group of voteables in one database query.
      # This returns an Arel relation, so you can add conditions as you like chained on to
      # this method call.
      # i.e. Posts.tally.where('votes.created_at > ?', 2.days.ago)
      # You can also have the upvotes and downvotes returned separately in the same query:
      # Post.plusminus_tally(:separate_updown => true)
      def plusminus_tally(params = {})
        t = self.joins("LEFT OUTER JOIN #{Vote.table_name} ON #{self.table_name}.id = #{Vote.table_name}.voteable_id")
        t = t.order("plusminus_tally DESC")
        t = t.group("#{self.table_name}.id")
        t = t.select("#{self.table_name}.*")
        t = t.select("SUM(CASE CAST(#{Vote.table_name}.vote AS UNSIGNED) WHEN 1 THEN 1 WHEN 0 THEN -1 ELSE 0 END) AS plusminus_tally")
        if params[:separate_updown]
          t = t.select("SUM(CASE CAST(#{Vote.table_name}.vote AS UNSIGNED) WHEN 1 THEN 1 WHEN 0 THEN 0 ELSE 0 END) AS up")
          t = t.select("SUM(CASE CAST(#{Vote.table_name}.vote AS UNSIGNED) WHEN 1 THEN 0 WHEN 0 THEN 1 ELSE 0 END) AS down")
        end
        t = t.select("COUNT(#{Vote.table_name}.id) AS vote_count")
      end

      # #rank_tally is depreciated.
      alias_method :rank_tally, :plusminus_tally

      # Calculate the vote counts for all voteables of my type.
      # This method returns all voteables (even without any votes) by default.
      # The vote count for each voteable is available as #vote_count.
      # This returns an Arel relation, so you can add conditions as you like chained on to
      # this method call.
      # i.e. Posts.tally.where('votes.created_at > ?', 2.days.ago)
      def tally(*args)
        t = self.joins("LEFT OUTER JOIN #{Vote.table_name} ON #{self.table_name}.id = #{Vote.table_name}.voteable_id")
        t = t.order("vote_count DESC")
        t = t.group("#{self.table_name}.id")
        t = t.select("#{self.table_name}.*")
        t = t.select("COUNT(#{Vote.table_name}.id) AS vote_count")
      end

      def column_names_for_tally
        column_names.map { |column| "#{self.table_name}.#{column}" }.join(', ')
      end

    end

    module InstanceMethods

      def votes_for
        self.votes.where(:vote => true).count - self.votes.where(:vote => true, :value => 0).count
      end

      def votes_against
        self.votes.where(:vote => false).count - self.votes.where(:vote => false, :value => 0).count
      end

      def tweets_for
        Vote.where(
              :voteable_id => self.id,
              :voteable_type => self.class.base_class.name
            ).count - Vote.where(
              :voteable_id => self.id,
              :voteable_type => self.class.base_class.name,
              :tweeted => 0
            ).count
      end


      def votes_skipped
        self.votes.where(:value => 0).count
      end

      def votes_high
        self.votes.where(:value => 100, :vote => true).count
      end

      def votes_medium
        self.votes.where(:value => 10, :vote => true).count
      end

      def votes_low
        self.votes.where(:value => 1, :vote => true).count
      end


      def percent_high
        (votes_high.to_f * 100 / (self.votes.size + 0.0001)).round
      end

      def percent_for
        (votes_for.to_f * 100 / (self.votes.size + 0.0001)).round
      end

      def percent_against
        (votes_against.to_f * 100 / (self.votes.size + 0.0001)).round
      end

      # You'll probably want to use this method to display how 'good' a particular voteable
      # is, and/or sort based on it.
      # If you're using this for a lot of voteables, then you'd best use the #plusminus_tally
      # method above.
      def plusminus
        respond_to?(:plusminus_tally) ? plusminus_tally : (votes_for - votes_against)
      end

      # The lower bound of a Wilson Score with a default confidence interval of 95%. Gives a more accurate representation of average rating (plusminus) based on the number of positive ratings and total ratings.
      # http://evanmiller.org/how-not-to-sort-by-average-rating.html
      def ci_plusminus(confidence = 0.95)
        require 'statistics2'
        n = votes.size
        if n == 0
          return 0
        end
        z = Statistics2.pnormaldist(1 - (1 - confidence) / 2)
        phat = 1.0 * votes_for / n
        (phat + z * z / (2 * n) - z * Math.sqrt((phat * (1 - phat) + z * z / (4 * n)) / n)) / (1 + z * z / n)
      end

      def votes_count
        #votes.size
        votes_for + votes_against
      end

      def voters_who_voted
        votes.map(&:voter).uniq
      end

      def voted_by?(voter)
        0 < Vote.where(
              :voteable_id => self.id,
              :voteable_type => self.class.base_class.name,
              :voter_id => voter.id
            ).count
      end

      def tweeted_by?(voter)
        Vote.where(
            :voter_id => voter.id,
            :voter_type => voter.class.base_class.name,
            :voteable_id => self.id,
            :voteable_type => self.class.base_class.name
          ).first ? Vote.where(
            :voter_id => voter.id,
            :voter_type => voter.class.base_class.name,
            :voteable_id => self.id,
            :voteable_type => self.class.base_class.name
          ).first.tweeted : 0
      end

    end
  end
end
