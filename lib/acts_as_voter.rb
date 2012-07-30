module ThumbsUp #:nodoc:
  module ActsAsVoter #:nodoc:

    def self.included(base)
      base.extend ClassMethods
    end

    module ClassMethods
      def acts_as_voter

        # If a voting entity is deleted, keep the votes.
        # If you want to nullify (and keep the votes), you'll need to remove
        # the unique constraint on the [ voter, voteable ] index in the database.
        # has_many :votes, :as => :voter, :dependent => :nullify
        # Destroy votes when a user is deleted.
        has_many :votes, :as => :voter, :dependent => :destroy

        include ThumbsUp::ActsAsVoter::InstanceMethods
        extend  ThumbsUp::ActsAsVoter::SingletonMethods
      end
    end

    # This module contains class methods
    module SingletonMethods
    end

    # This module contains instance methods
    module InstanceMethods

      # Usage user.vote_count(:up)  # All +1 votes
      #       user.vote_count(:down) # All -1 votes
      #       user.vote_count()      # All votes

      def vote_count(for_or_against = :all)
        v = Vote.where(:voter_id => id).where(:voter_type => self.class.base_class.name)
        v = case for_or_against
          when :all   then v
          when :up    then v.where(:vote => true)
          when :down  then v.where(:vote => false)
        end
        v.count
      end

      def voted_for?(voteable)
        voted_skip?(voteable) ? false : voted_which_way?(voteable, :up)
      end

      def voted_against?(voteable)
        voted_skip?(voteable) ? false : voted_which_way?(voteable, :down)
      end

      def voted_skip?(voteable)
        voted_value?(voteable, 0)
      end
      def voted_low?(voteable)
        return false unless voted_for?(voteable)
        voted_value?(voteable, 1)
      end
      def voted_medium?(voteable)
        return false unless voted_for?(voteable)
        voted_value?(voteable, 10)
      end
      def voted_high?(voteable)
        return false unless voted_for?(voteable)
        voted_value?(voteable, 100)
      end


      def voted_value?(voteable, weight)
       0 < Vote.where(
              :voter_id => self.id,
              :voter_type => self.class.base_class.name,
              :voteable_id => voteable.id,
              :voteable_type => voteable.class.base_class.name,
              :value => weight
            ).count
      end


      def voted_on?(voteable)
        0 < Vote.where(
              :voter_id => self.id,
              :voter_type => self.class.base_class.name,
              :voteable_id => voteable.id,
              :voteable_type => voteable.class.base_class.name
            ).count
      end

      def vote_for(voteable, importance)
        self.vote(voteable, { :direction => :up, :exclusive => false, :value => importance })
      end

      def vote_against(voteable, importance=:against)
        importance=:against
        self.vote(voteable, { :direction => :down, :exclusive => false, :value => importance })
      end

      def vote_exclusively_for(voteable, importance)
        self.vote(voteable, { :direction => :up, :exclusive => true, :value => importance })
      end

      def vote_exclusively_against(voteable, importance=:against)
        importance=:against
        self.vote(voteable, { :direction => :down, :exclusive => true, :value => importance })
      end

      def vote(voteable, options = {})
        raise ArgumentError, "you must specify :up or :down in order to vote" unless options[:direction] && [:up, :down].include?(options[:direction].to_sym)
        remember_tweet = self.tweeted?(voteable) #because the unvote will wipe it out
        if options[:exclusive]
          self.unvote_for(voteable)
        end
        direction = (options[:direction].to_sym == :up)
        case options[:value]
          when :high
            weight = 100
          when :medium
            weight = 10
          when :low
            weight = 1
          when :against
            weight = -1
          when :skip
            weight = 0
          else
            weight = 0
        end
        @vote = Vote.new(:vote => direction, :value => weight, :tweeted => remember_tweet)
        @vote.voteable = voteable
        @vote.voter = self
        @vote.save!
      end


      def tweet_for(voteable)
          vote_exclusively_for(voteable, :skip) unless 
              Vote.where(
                  :voter_id => self.id,
                  :voter_type => self.class.base_class.name,
                  :voteable_id => voteable.id,
                  :voteable_type => voteable.class.base_class.name).count > 0
          Vote.where(
                :voter_id => self.id,
                :voter_type => self.class.base_class.name,
                :voteable_id => voteable.id,
                :voteable_type => voteable.class.base_class.name).first.increment(:tweeted)
      end


      def tweeted?(voteable)
        Vote.where(
            :voter_id => self.id,
            :voter_type => self.class.base_class.name,
            :voteable_id => voteable.id,
            :voteable_type => voteable.class.base_class.name
          ).first ? Vote.where(
            :voter_id => self.id,
            :voter_type => self.class.base_class.name,
            :voteable_id => voteable.id,
            :voteable_type => voteable.class.base_class.name
          ).first.tweeted : 0
      end

      def unvote_for(voteable)
        Vote.where(
          :voter_id => self.id,
          :voter_type => self.class.base_class.name,
          :voteable_id => voteable.id,
          :voteable_type => voteable.class.base_class.name
        ).map(&:destroy)
      end

      alias_method :clear_votes, :unvote_for

      def voted_which_way?(voteable, direction)
        raise ArgumentError, "expected :up or :down" unless [:up, :down].include?(direction)
        0 < Vote.where(
              :voter_id => self.id,
              :voter_type => self.class.base_class.name,
              :vote => direction == :up ? true : false,
              :voteable_id => voteable.id,
              :voteable_type => voteable.class.base_class.name
            ).count
      end

    end
  end
end
